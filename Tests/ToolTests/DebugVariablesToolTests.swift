//
//  DebugVariablesToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_variables")
struct DebugVariablesToolTests {

    @Test("Returns frame variables for current frame")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-vars",
            commandResponses: ["frame variable": "(String) name = \"hello\"\n(Int) count = 42"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_variables",
            arguments: ["session_id": .string("dbg-vars")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("name"))
            #expect(result.content.contains("count"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Selects specific frame before fetching variables")
    func specificFrame() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-vars2",
            commandResponses: [
                "frame select 2": "frame #2: 0x00007fff caller_func",
                "frame variable": "(Bool) isEnabled = true",
            ]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_variables",
            arguments: [
                "session_id": .string("dbg-vars2"),
                "frame_index": .int(2),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("isEnabled"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_variables",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
