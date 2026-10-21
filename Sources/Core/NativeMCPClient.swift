// Created by Jared Manfredi

import Foundation
import MCP

/// The narrow native API surface used by the UI pilot; raw replies stay inside this boundary.
protocol NativeMCPCalling: Sendable {
    func connect() async throws
    func call(_ name: String, arguments: [String: Value], timeout: TimeInterval) async throws -> [String: Value]
    func close() async
}

actor NativeMCPClient: NativeMCPCalling {
    private var client: Client?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private let testTransport: (any Transport)?

    init() { testTransport = nil }

    init(transport: any Transport) { testTransport = transport }

    func connect() async throws {
        try Task.checkCancellation()
        guard client == nil else { return }
        let client = Client(name: "ios-mcp-native-ui", version: "0.1")
        self.client = client
        do {
            let transport: any Transport
            if let testTransport {
                transport = testTransport
            } else {
                let input = Pipe()
                let output = Pipe()
                self.input = input
                self.output = output
                self.process = try CommandExecutor().launchNativeMCPBridge(input: input, output: output)
                transport = StdioTransport(
                    input: .init(rawValue: output.fileHandleForReading.fileDescriptor),
                    output: .init(rawValue: input.fileHandleForWriting.fileDescriptor)
                )
            }
            _ = try await bounded(client: client, seconds: 15) {
                try await client.connect(transport: transport)
            }
            var tools: [Tool] = []
            var cursor: String?
            for _ in 0..<10 {
                let pageCursor = cursor
                let page = try await bounded(client: client, seconds: 10) {
                    try await client.listTools(cursor: pageCursor)
                }
                tools += page.tools
                cursor = page.nextCursor
                if cursor == nil { break }
            }
            guard cursor == nil else {
                throw ToolError(code: .dependencyMissing, message: "Native Xcode tool catalog exceeded the page limit.")
            }
            try Self.validateCatalog(tools)
        } catch {
            await close()
            throw Self.safeError(error)
        }
    }

    func call(_ name: String, arguments: [String: Value], timeout: TimeInterval) async throws -> [String: Value] {
        try Task.checkCancellation()
        guard let client else {
            throw ToolError(code: .commandFailed, message: "Native Xcode connection is not open.")
        }
        do {
            let result: CallTool.Result = try await bounded(client: client, seconds: timeout) {
                let context = try await client.send(CallTool.request(.init(name: name, arguments: arguments)))
                return try await context.value
            }
            if result.isError == true {
                // The server can echo session keys. Never forward raw native errors.
                let text = result.content.compactMap { content -> String? in
                    if case .text(let text, _, _) = content { return text.lowercased() }
                    return nil
                }.joined(separator: " ")
                if text.contains("approv") || text.contains("permission") {
                    throw ToolError(code: .commandDenied, message: "Xcode denied native UI access. Approve this agent and the selected project folder in Xcode, then retry.")
                }
                throw ToolError(code: .commandFailed, message: "Native Xcode tool \(name) failed.")
            }
            if case .object(let object) = result.structuredContent { return object }
            for content in result.content {
                if case .text(let text, _, _) = content,
                   let object = try? JSONDecoder().decode([String: Value].self, from: Data(text.utf8)) {
                    return object
                }
            }
            throw ToolError(code: .commandFailed, message: "Native Xcode tool \(name) returned an unsupported response format.")
        } catch {
            // A timeout/cancellation has an unknown server-side outcome. Closing
            // the transport unblocks pending SDK requests; never replay the action.
            if !(error is ToolError) || (error as? ToolError)?.code == .timeout {
                await close()
            }
            throw Self.safeError(error)
        }
    }

    func close() async {
        let client = self.client
        let process = self.process
        self.client = nil
        self.process = nil
        await client?.disconnect()
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            // Do not block Swift's cooperative pool while waiting for the child.
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? input?.fileHandleForReading.close()
        try? output?.fileHandleForReading.close()
        try? output?.fileHandleForWriting.close()
        input = nil
        output = nil
    }

    static func validateCatalog(_ tools: [Tool]) throws {
        let expected = [
            "XcodeOpenWorkspace": ["path"],
            "DeviceInteractionStartSession": ["deviceIdentifier", "sessionIdentifier"],
            "DeviceInteractionSynthesize": ["interactSessionKey", "interactionCommand"],
            "DeviceInteractionEndSession": ["interactionSessionKey"],
        ]
        for (name, fields) in expected {
            guard let tool = tools.first(where: { $0.name == name }),
                  case .object(let schema) = tool.inputSchema,
                  schema["type"] == .string("object"),
                  case .object(let properties) = schema["properties"],
                  case .array(let required) = schema["required"],
                  required.allSatisfy({ field in
                      guard case .string(let field) = field else { return false }
                      // Captures omit interactionCommand; it must remain optional.
                      return fields.contains(field) && !(name == "DeviceInteractionSynthesize" && field == "interactionCommand")
                  }),
                  fields.allSatisfy({ field in
                      guard case .object(let property) = properties[field] else { return false }
                      return property["type"] == .string("string")
                  }) else {
                throw ToolError(code: .dependencyMissing, message: "The selected Xcode does not expose the native UI schema required for \(name).")
            }
        }
    }

    private func bounded<T: Sendable>(client: Client, seconds: TimeInterval,
                                     operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try Task.checkCancellation()
                    return try await operation()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(seconds))
                    throw ToolError(code: .timeout, message: "Native Xcode request timed out; its outcome may be unknown. Do not automatically retry a tap.")
                }
                do {
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    await client.disconnect()
                    throw error
                }
            }
        } onCancel: {
            Task { await client.disconnect() }
        }
    }

    private static func safeError(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let error = error as? ToolError { return error }
        return ToolError(code: .commandFailed, message: "Native Xcode connection failed. Check Xcode availability and agent authorization.")
    }
}

extension CommandExecutor {
    /// Interactive MCP frames contain private session keys and must not be logged
    /// or redacted in transit. NativeMCPClient sanitizes errors at the boundary.
    func launchNativeMCPBridge(input: Pipe, output: Pipe) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["mcpbridge"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Do not inherit an unrelated client's explicit Xcode/session selection.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "MCP_XCODE_PID")
        environment.removeValue(forKey: "MCP_XCODE_SESSION_ID")
        process.environment = environment
        try process.run()
        return process
    }
}
