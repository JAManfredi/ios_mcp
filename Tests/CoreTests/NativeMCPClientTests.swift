// Created by Jared Manfredi

import Foundation
import Logging
import MCP
import Testing
@testable import Core

private let nativeSchemaFields = [
    "XcodeOpenWorkspace": ["path"],
    "DeviceInteractionStartSession": ["deviceIdentifier", "sessionIdentifier"],
    "DeviceInteractionSynthesize": ["interactSessionKey", "interactionCommand"],
    "DeviceInteractionEndSession": ["interactionSessionKey"],
]

private actor NativeTestTransport: Transport {
    nonisolated let logger = Logger(label: "native-test", factory: { _ in SwiftLogNoOpLogHandler() })
    let stream: AsyncThrowingStream<Data, Error>
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    let mode: String
    private(set) var disconnected = false
    private(set) var callReceived = false

    init(mode: String = "structured") {
        self.mode = mode
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }
    func connect() {}
    func disconnect() { disconnected = true; continuation.finish() }
    func receive() -> AsyncThrowingStream<Data, Error> { stream }
    func send(_ data: Data) throws {
        let request = try JSONDecoder().decode([String: Value].self, from: data)
        guard let id = request["id"] else { return }
        let result: Value
        switch request["method"] {
        case .string("initialize"):
            result = .object(["protocolVersion": .string("2024-11-05"), "capabilities": .object(["tools": .object([:])]),
                              "serverInfo": .object(["name": .string("fixture"), "version": .string("1")])])
        case .string("tools/list"):
            let tools: [Value] = nativeSchemaFields.map { name, fields in
                var properties = fields.reduce(into: [String: Value]()) { $0[$1] = .object(["type": .string("string")]) }
                if mode == "schema" { properties.removeValue(forKey: "interactSessionKey") }
                let required = fields.filter { $0 != "interactionCommand" } + (mode == "new-required" ? ["unknown"] : [])
                return .object(["name": .string(name), "description": .string("fixture"),
                                "inputSchema": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(Value.string))])])
            }
            result = .object(["tools": .array(tools)])
        default:
            callReceived = true
            switch mode {
            case "silent": return
            case "denied", "error":
                result = .object(["isError": .bool(true), "content": .array([.object(["type": .string("text"), "text": .string("\(mode == "denied" ? "permission approval" : "failed") private-key")])])])
            case "text":
                result = .object(["content": .array([.object(["type": .string("text"), "text": .string("{\"value\":42}")])])])
            default:
                result = .object(["content": .array([]), "structuredContent": .object(["value": .int(42)])])
            }
        }
        continuation.yield(try JSONEncoder().encode(["jsonrpc": Value.string("2.0"), "id": id, "result": result]))
    }
    func waitForCall() async throws {
        for _ in 0..<1000 {
            if callReceived { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw CancellationError()
    }
}

@Suite("Native MCP transport")
struct NativeMCPClientTests {
    @Test(arguments: ["structured", "text"])
    func readsBothResponseFormats(mode: String) async throws {
        let transport = NativeTestTransport(mode: mode)
        let client = NativeMCPClient(transport: transport)
        try await client.connect()
        #expect(try await client.call("Fixture", arguments: [:], timeout: 1)["value"] == .int(42))
        await client.close()
        #expect(await transport.disconnected)
    }

    @Test(arguments: ["schema", "new-required"])
    func incompatibleCatalogClosesConnection(mode: String) async throws {
        let transport = NativeTestTransport(mode: mode)
        let client = NativeMCPClient(transport: transport)
        do { try await client.connect(); Issue.record("Expected compatibility error") }
        catch let error as ToolError { #expect(error.code == .dependencyMissing) }
        #expect(await transport.disconnected)
    }

    @Test(arguments: ["denied", "error"])
    func nativeErrorsCannotLeakSessionKeys(mode: String) async throws {
        let transport = NativeTestTransport(mode: mode)
        let client = NativeMCPClient(transport: transport)
        try await client.connect()
        do { _ = try await client.call("Fixture", arguments: [:], timeout: 1); Issue.record("Expected error") }
        catch let error as ToolError {
            #expect(error.code == (mode == "denied" ? .commandDenied : .commandFailed))
            #expect(!error.message.contains("private-key"))
        }
        // Ordinary errors leave the connection available for EndSession.
        #expect(await transport.disconnected == false)
        await client.close()
    }

    @Test func timeoutUnblocksPendingSDKRequest() async throws {
        let transport = NativeTestTransport(mode: "silent")
        let client = NativeMCPClient(transport: transport)
        try await client.connect()
        do { _ = try await client.call("Fixture", arguments: [:], timeout: 0.02); Issue.record("Expected timeout") }
        catch let error as ToolError { #expect(error.code == .timeout) }
        #expect(await transport.disconnected)
    }

    @Test func cancellationUnblocksPendingSDKRequest() async throws {
        let transport = NativeTestTransport(mode: "silent")
        let client = NativeMCPClient(transport: transport)
        try await client.connect()
        let task = Task { try await client.call("Fixture", arguments: [:], timeout: 60) }
        try await transport.waitForCall()
        task.cancel()
        _ = await task.result
        #expect(await transport.disconnected)
    }
}
