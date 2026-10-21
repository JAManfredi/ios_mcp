// Created by Jared Manfredi

import Foundation
import MCP

public protocol NativeUIAutomating: Sendable {
    func inspect(udid: String) async throws -> ToolResult
    func tap(udid: String, target: NativeUITarget) async throws -> ToolResult
}

/// Opt-in pilot. One operation owns one bridge and one device interaction session.
/// No action is retried or sent to AXe after a native failure.
public actor NativeUIController: NativeUIAutomating {
    private let workspace: String
    private let artifacts: ArtifactStore
    private let concurrency: ConcurrencyPolicy
    private let makeClient: @Sendable () -> any NativeMCPCalling
    private let artifactRoot: URL
    private var active: Task<ToolResult, Error>?
    private var stopping = false

    public init(workspace: String, artifacts: ArtifactStore, concurrency: ConcurrencyPolicy) throws {
        let url = URL(fileURLWithPath: workspace).standardizedFileURL
        guard workspace.hasPrefix("/"), ["xcodeproj", "xcworkspace"].contains(url.pathExtension),
              FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(code: .invalidInput, message: "--native-ui-workspace requires an existing absolute .xcodeproj or .xcworkspace path.")
        }
        self.workspace = url.path
        self.artifacts = artifacts
        self.concurrency = concurrency
        self.makeClient = { NativeMCPClient() }
        self.artifactRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ActionArtifacts")
    }

    init(workspace: String, artifacts: ArtifactStore, concurrency: ConcurrencyPolicy,
         artifactRoot: URL, makeClient: @escaping @Sendable () -> any NativeMCPCalling) {
        self.workspace = workspace
        self.artifacts = artifacts
        self.concurrency = concurrency
        self.artifactRoot = artifactRoot
        self.makeClient = makeClient
    }

    public func inspect(udid: String) async throws -> ToolResult {
        try await perform(udid: udid, target: nil)
    }

    public func tap(udid: String, target: NativeUITarget) async throws -> ToolResult {
        try await perform(udid: udid, target: target)
    }

    public func shutdown() async {
        stopping = true
        active?.cancel()
        _ = await active?.result
    }

    private func perform(udid: String, target: NativeUITarget?) async throws -> ToolResult {
        try Task.checkCancellation()
        guard !stopping, active == nil else {
            throw ToolError(code: .resourceBusy, message: "Native UI is busy or shutting down. Wait for the current operation to finish.")
        }
        guard let uuid = UUID(uuidString: udid) else {
            throw ToolError(code: .invalidInput, message: "Native UI requires an exact simulator UUID, not a device name or partial identifier.")
        }
        let task = Task { [workspace, artifacts, concurrency, artifactRoot, makeClient] in
            try await Self.run(udid: uuid.uuidString, target: target, workspace: workspace,
                               artifacts: artifacts, concurrency: concurrency,
                               artifactRoot: artifactRoot, client: makeClient())
        }
        active = task
        defer { active = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private static func run(udid: String, target: NativeUITarget?, workspace: String,
                            artifacts: ArtifactStore, concurrency: ConcurrencyPolicy,
                            artifactRoot: URL, client: any NativeMCPCalling) async throws -> ToolResult {
        let lock = "simulator:\(udid)"
        if let error = await concurrency.acquire(key: lock, owner: "native_ui") { throw error }
        var sessionKey: String?
        var startRequested = false
        var tapRequested = false
        var outcome: Result<ToolResult, Error>
        do {
            try await client.connect()
            _ = try await client.call("XcodeOpenWorkspace", arguments: ["path": .string(workspace)], timeout: 120)
            try Task.checkCancellation()
            startRequested = true
            let started = try await client.call("DeviceInteractionStartSession", arguments: [
                "deviceIdentifier": .string(udid), "sessionIdentifier": .string("ios-mcp UI pilot \(UUID().uuidString)"),
            ], timeout: 120)
            if case .string(let key) = started["interactionSessionKey"], !key.isEmpty { sessionKey = key }
            guard let key = sessionKey, started["deviceIsSimulator"] == .bool(true),
                  case .string(let actual) = started["deviceUUID"], UUID(uuidString: actual)?.uuidString == udid else {
                throw ToolError(code: .commandFailed, message: "Xcode did not confirm the exact requested simulator. No UI action was sent.")
            }
            try Task.checkCancellation()
            var reply = try await client.call("DeviceInteractionSynthesize", arguments: ["interactSessionKey": .string(key)], timeout: 120)
            var capture = try NativeUICapture(reply: reply, sessionKey: key, artifactRoot: artifactRoot)
            let hierarchy = try NativeUIHierarchy(text: capture.hierarchy)
            if let target {
                let point = try hierarchy.point(for: target)
                try Task.checkCancellation()
                tapRequested = true
                reply = try await client.call("DeviceInteractionSynthesize", arguments: [
                    "interactSessionKey": .string(key),
                    "interactionCommand": .string("t \(Double(point.x)) \(Double(point.y))"),
                ], timeout: 120)
                capture = try NativeUICapture(reply: reply, sessionKey: key, artifactRoot: artifactRoot)
                _ = try NativeUIHierarchy(text: capture.hierarchy)
            }
            try Task.checkCancellation()
            let text = sanitized(capture.hierarchy, key: key)
            let screenshot = try await artifacts.store(data: capture.screenshot, filename: "native-ui.png", mimeType: "image/png")
            let tree = try await artifacts.store(data: Data(text.utf8), filename: "native-ui.txt", mimeType: "text/plain")
            guard [screenshot, tree].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw ToolError(code: .commandFailed, message: "Managed capture storage is full; capture files were evicted.")
            }
            try Task.checkCancellation()
            outcome = .success(ToolResult(
                content: "Native Xcode UI\(target == nil ? " inspection" : " tap completed"). Coordinates are screen points.\nScreenshot: \(screenshot.path)\nHierarchy: \(tree.path)\n\n\(text)",
                artifacts: [screenshot, tree], inlineArtifacts: false
            ))
        } catch {
            let known = error as? ToolError
            var message = error is CancellationError ? "Native UI operation was cancelled." : known?.message ?? "Native UI operation failed."
            if tapRequested { message += " The tap may have occurred. Inspect the screen before deciding whether to tap again; no retry or AXe fallback was attempted." }
            if startRequested && sessionKey == nil { message += " Session creation was not confirmed; Xcode may have an orphaned interaction session. Check Xcode before retrying." }
            outcome = .failure(ToolError(code: known?.code ?? .commandFailed, message: sanitized(message, key: sessionKey)))
        }

        // Cleanup must run even when the caller's task was cancelled. Reconnect
        // only to end a known session, never to replay a UI action.
        let key = sessionKey
        let ended = await Task.detached {
            var ended = true
            if let key {
                do {
                    try await client.connect()
                    _ = try await client.call("DeviceInteractionEndSession", arguments: ["interactionSessionKey": .string(key)], timeout: 15)
                } catch { ended = false }
            }
            await client.close()
            return ended
        }.value
        await concurrency.release(key: lock)
        if !ended {
            let suffix = " Native session cleanup was not confirmed. Check Xcode's device interaction sessions before continuing."
            if case .failure(let error as ToolError) = outcome {
                throw ToolError(code: error.code, message: error.message + suffix)
            }
            throw ToolError(code: .commandFailed, message: "Native UI operation completed." + suffix)
        }
        return try outcome.get()
    }

    private static func sanitized(_ text: String, key: String?) -> String {
        Redactor.redact(key.map { text.replacingOccurrences(of: $0, with: "[REDACTED]") } ?? text)
    }
}
