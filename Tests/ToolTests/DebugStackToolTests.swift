//
//  DebugStackToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_stack")
struct DebugStackToolTests {

    @Test("Returns backtrace for current thread")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-stack",
            commandResponses: ["bt": "* thread #1, queue = 'com.apple.main-thread'\n  frame #0: 0x00007fff viewDidLoad"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator())

        let response = try await registry.callTool(
            name: "debug_stack",
            arguments: ["session_id": .string("dbg-stack")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("thread #1"))
            #expect(result.content.contains("viewDidLoad"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Returns backtrace for specific thread")
    func specificThread() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-stack2",
            commandResponses: ["thread backtrace 3": "* thread #3\n  frame #0: worker_func"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator())

        let response = try await registry.callTool(
            name: "debug_stack",
            arguments: [
                "session_id": .string("dbg-stack2"),
                "thread_id": .int(3),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("thread #3"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "debug_stack",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
