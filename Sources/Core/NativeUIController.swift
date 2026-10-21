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
    private let workspace: String?
    private let mode: UIBackendMode
    private let session: SessionStore?
    private let executor: any CommandExecuting
    private let validator: DefaultsValidator
    private let artifacts: ArtifactStore
    private let concurrency: ConcurrencyPolicy
    private let makeClient: @Sendable () -> any NativeMCPCalling
    private let artifactRoot: URL
    private var active: [String: Task<ToolResult, Error>] = [:]
    private var stopping = false

    private static func validatedWorkspace(_ workspace: String, validator: DefaultsValidator) throws -> String {
        let url = URL(fileURLWithPath: workspace).standardizedFileURL
        guard workspace.hasPrefix("/"), ["xcodeproj", "xcworkspace"].contains(url.pathExtension) else {
            throw ToolError(code: .invalidInput, message: "Native UI requires an existing absolute .xcodeproj or .xcworkspace path. Check --native-ui-workspace or session workspace/project defaults.")
        }
        if let error = validator.validatePathExists(url.path, label: "Native UI project") { throw error }
        return url.path
    }

    public init(workspace: String? = nil, mode: UIBackendMode = .native, session: SessionStore? = nil,
                executor: any CommandExecuting = CommandExecutor(), artifacts: ArtifactStore, concurrency: ConcurrencyPolicy,
                validator: DefaultsValidator? = nil) throws {
        let validator = validator ?? DefaultsValidator(executor: executor, pathPolicy: PathPolicy())
        self.validator = validator
        self.workspace = try workspace.map { try Self.validatedWorkspace($0, validator: validator) }
        self.mode = mode
        self.session = session
        self.executor = executor
        self.artifacts = artifacts
        self.concurrency = concurrency
        self.makeClient = { NativeMCPClient() }
        self.artifactRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ActionArtifacts")
    }

    init(workspace: String?, artifacts: ArtifactStore, concurrency: ConcurrencyPolicy,
         artifactRoot: URL, mode: UIBackendMode = .native, session: SessionStore? = nil,
         executor: any CommandExecuting = CommandExecutor(), validator: DefaultsValidator? = nil,
         makeClient: @escaping @Sendable () -> any NativeMCPCalling) {
        self.workspace = workspace
        self.mode = mode
        self.session = session
        self.executor = executor
        self.validator = validator ?? DefaultsValidator(executor: executor, pathPolicy: PathPolicy())
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
        let tasks = Array(active.values)
        for task in tasks { task.cancel() }
        for task in tasks { _ = await task.result }
    }

    private func perform(udid: String, target: NativeUITarget?) async throws -> ToolResult {
        try Task.checkCancellation()
        let deviceKey = UUID(uuidString: udid)?.uuidString ?? udid
        guard !stopping, active[deviceKey] == nil else {
            throw ToolError(code: .resourceBusy, message: "Native UI is busy on this simulator or shutting down. Wait for the current operation to finish.")
        }
        if mode == .axe { throw NativeUIUnavailable("axe mode") }
        // Take one snapshot: an operation must not combine workspace/project
        // defaults from different session updates.
        let defaults = await session?.allDefaults() ?? [:]
        try Task.checkCancellation()
        // The defaults snapshot awaited another actor; recheck ownership before
        // publishing this task so concurrent calls cannot replace active work.
        guard !stopping, active[deviceKey] == nil else {
            throw ToolError(code: .resourceBusy, message: "Native UI is busy or shutting down.")
        }
        let selectedWorkspace = workspace ?? defaults[.workspace] ?? defaults[.project]
        guard let selectedWorkspace else {
            if mode == .auto { throw NativeUIUnavailable("auto: no workspace/project configured") }
            throw ToolError(code: .invalidInput, message: "Native UI needs --native-ui-workspace or a session workspace/project default.")
        }
        let selectedPath = try Self.validatedWorkspace(selectedWorkspace, validator: validator)
        guard let uuid = UUID(uuidString: udid) else {
            throw ToolError(code: .invalidInput, message: "Native UI requires an exact simulator UUID, not a device name or partial identifier.")
        }
        let task = Task { [mode, executor, artifacts, concurrency, artifactRoot, makeClient] in
            try await Self.run(udid: uuid.uuidString, target: target, workspace: selectedPath, mode: mode, executor: executor,
                               artifacts: artifacts, concurrency: concurrency,
                               artifactRoot: artifactRoot, client: makeClient())
        }
        active[deviceKey] = task
        defer { active[deviceKey] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private static func run(udid: String, target: NativeUITarget?, workspace: String, mode: UIBackendMode, executor: any CommandExecuting,
                            artifacts: ArtifactStore, concurrency: ConcurrencyPolicy,
                            artifactRoot: URL, client: any NativeMCPCalling) async throws -> ToolResult {
        let lock = "simulator:\(udid)"
        if let error = await concurrency.acquire(key: lock, owner: "native_ui") { throw error }
        // This is the only fallback boundary. Catalog discovery performs no
        // workspace, permission, device-session, or input tool calls.
        do {
            if mode == .auto {
                let found = try await executor.execute(executable: "/usr/bin/xcrun", arguments: ["--find", "mcpbridge"], timeout: 5, environment: nil)
                try Task.checkCancellation()
                if !found.succeeded && found.stderr.contains("unable to find utility \"mcpbridge\"") {
                    throw NativeUIUnavailable("auto: mcpbridge is unavailable in the selected Xcode")
                }
                let path = found.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard found.succeeded, path.hasPrefix("/"), !path.contains("\n") else {
                    throw ToolError(code: .commandFailed, message: "Native UI capability lookup failed; availability is unknown. No AXe fallback was attempted.")
                }
            }
            do { try await client.connect() }
            catch let error as ToolError where mode == .auto && error.code == .dependencyMissing {
                throw NativeUIUnavailable("auto: the selected Xcode lacks the required native UI tool schemas")
            }
            try Task.checkCancellation()
        } catch {
            await client.close()
            await concurrency.release(key: lock)
            try Task.checkCancellation()
            throw error
        }
        var sessionKey: String?
        var startRequested = false
        var tapRequested = false
        var outcome: Result<ToolResult, Error>
        do {
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
                content: "UI backend: native (\(mode == .auto ? "auto: required schemas available and project access succeeded" : "explicit native mode")).\nNative Xcode UI\(target == nil ? " inspection" : " tap completed"). Coordinates are screen points.\nScreenshot: \(screenshot.path)\nHierarchy: \(tree.path)\n\n\(text)",
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
