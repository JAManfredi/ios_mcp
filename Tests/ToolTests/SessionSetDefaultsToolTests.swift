//
//  SessionSetDefaultsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("session_set_defaults")
struct SessionSetDefaultsToolTests {

    @Test("Sets a single session key")
    func setSingleKey() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "session_set_defaults",
            arguments: ["simulator_udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("simulator_udid = AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let udid = await session.get(.simulatorUDID)
        #expect(udid == "AAAA-1111")
    }

    @Test("Sets multiple session keys")
    func setMultipleKeys() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "session_set_defaults",
            arguments: [
                "workspace": .string("/path/to/App.xcworkspace"),
                "scheme": .string("MyScheme"),
                "configuration": .string("Release"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("workspace = /path/to/App.xcworkspace"))
            #expect(result.content.contains("scheme = MyScheme"))
            #expect(result.content.contains("configuration = Release"))
        } else {
            Issue.record("Expected success response")
        }

        let ws = await session.get(.workspace)
        let scheme = await session.get(.scheme)
        let config = await session.get(.configuration)
        #expect(ws == "/path/to/App.xcworkspace")
        #expect(scheme == "MyScheme")
        #expect(config == "Release")
    }

    @Test("Rejects empty call with no arguments")
    func rejectsEmpty() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "session_set_defaults", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("At least one"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Sets all supported keys")
    func setsAllKeys() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "session_set_defaults",
            arguments: [
                "simulator_udid": .string("UUID-123"),
                "workspace": .string("/ws.xcworkspace"),
                "project": .string("/proj.xcodeproj"),
                "scheme": .string("Scheme"),
                "bundle_id": .string("com.test"),
                "configuration": .string("Debug"),
                "derived_data_path": .string("/tmp/dd"),
            ]
        )

        if case .success = response {
            #expect(await session.get(.simulatorUDID) == "UUID-123")
            #expect(await session.get(.workspace) == "/ws.xcworkspace")
            #expect(await session.get(.project) == "/proj.xcodeproj")
            #expect(await session.get(.scheme) == "Scheme")
            #expect(await session.get(.bundleID) == "com.test")
            #expect(await session.get(.configuration) == "Debug")
            #expect(await session.get(.derivedDataPath) == "/tmp/dd")
        } else {
            Issue.record("Expected success response")
        }
    }
}
