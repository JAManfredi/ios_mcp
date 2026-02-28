//
//  DebugLLDBCommandToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_run_command")
struct DebugLLDBCommandToolTests {

    @Test("Executes allowed command")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-cmd1",
            commandResponses: ["po self.view": "(UIView) 0x7fff12345678"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-cmd1"),
                "command": .string("po self.view"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("UIView"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Denies blocked command")
    func deniedCommand() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-cmd2")
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-cmd2"),
                "command": .string("platform shell ls"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandDenied)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Bypasses denylist with allow_unsafe flag")
    func allowUnsafeBypass() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-cmd3",
            commandResponses: ["platform shell ls": "/tmp\n/var"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-cmd3"),
                "command": .string("platform shell ls"),
                "allow_unsafe": .bool(true),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("[UNSAFE]"))
            #expect(result.content.contains("/tmp"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Sets unsafeCommandExecuted flag when allow_unsafe is true")
    func unsafeCommandExecutedFlag() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-flag",
            commandResponses: ["memory write 0x1000 0xFF": "done"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-flag"),
                "command": .string("memory write 0x1000 0xFF"),
                "allow_unsafe": .bool(true),
            ]
        )

        if case .success(let result) = response {
            #expect(result.unsafeCommandExecuted == true)
            #expect(result.content.contains("[UNSAFE]"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Does not set unsafeCommandExecuted flag for normal commands")
    func normalCommandNoFlag() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-noflag",
            commandResponses: ["bt": "frame #0"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-noflag"),
                "command": .string("bt"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.unsafeCommandExecuted == false)
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when command is missing")
    func missingCommand() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "debug_run_command",
            arguments: ["command": .string("bt")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Audit logs the command sent to session")
    func auditLogged() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(
            nextSessionID: "dbg-audit",
            commandResponses: ["thread info": "thread #1"]
        )
        _ = try await mockDebug.attach(pid: 1, bundleID: nil, udid: nil)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        _ = try await registry.callTool(
            name: "debug_run_command",
            arguments: [
                "session_id": .string("dbg-audit"),
                "command": .string("thread info"),
            ]
        )

        let lastCmd = await mockDebug.lastCommand
        #expect(lastCmd == "thread info")
    }
}
