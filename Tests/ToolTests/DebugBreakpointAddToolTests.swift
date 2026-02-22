//
//  DebugBreakpointAddToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_breakpoint_add")
struct DebugBreakpointAddToolTests {

    @Test("Adds breakpoint by symbol name")
    func happyPathSymbol() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-bp1",
            commandResponses: ["breakpoint set --name viewDidLoad": "Breakpoint 1: where = MyApp`viewDidLoad"]
        )
        // Pre-attach the session so sendCommand works
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug)

        let response = try await registry.callTool(
            name: "debug_breakpoint_add",
            arguments: [
                "session_id": .string("dbg-bp1"),
                "symbol": .string("viewDidLoad"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Breakpoint 1"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Adds breakpoint by file:line")
    func happyPathFileLine() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-bp2",
            commandResponses: ["breakpoint set --file ViewController.swift --line 42": "Breakpoint 1: file = ViewController.swift, line = 42"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug)

        let response = try await registry.callTool(
            name: "debug_breakpoint_add",
            arguments: [
                "session_id": .string("dbg-bp2"),
                "file": .string("ViewController.swift"),
                "line": .int(42),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("line = 42"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no symbol or file/line provided")
    func missingTarget() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(
            name: "debug_breakpoint_add",
            arguments: ["session_id": .string("any")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(
            name: "debug_breakpoint_add",
            arguments: ["symbol": .string("viewDidLoad")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
