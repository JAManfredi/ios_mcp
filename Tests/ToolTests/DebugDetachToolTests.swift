//
//  DebugDetachToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_detach")
struct DebugDetachToolTests {

    @Test("Detaches from active session")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-xyz")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug)

        // First attach
        _ = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(1234), "udid": .string("SIM-1111")]
        )

        // Then detach
        let response = try await registry.callTool(
            name: "debug_detach",
            arguments: ["session_id": .string("dbg-xyz")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("detached"))
            #expect(result.content.contains("dbg-xyz"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(
            name: "debug_detach",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when session_id is unknown")
    func unknownSession() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(
            name: "debug_detach",
            arguments: ["session_id": .string("nonexistent")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
