//
//  DebugContinueToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_resume")
struct DebugContinueToolTests {

    @Test("Sends continue and returns output")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-cont",
            commandResponses: ["continue": "Process 1234 resuming"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_resume",
            arguments: ["session_id": .string("dbg-cont")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("resuming"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_resume",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
