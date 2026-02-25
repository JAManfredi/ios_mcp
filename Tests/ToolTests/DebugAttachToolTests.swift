//
//  DebugAttachToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("debug_attach")
struct DebugAttachToolTests {

    @Test("Attaches by PID and returns session ID")
    func happyPathPID() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-aaa")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(1234), "udid": .string("SIM-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("dbg-aaa"))
            #expect(result.content.contains("SIM-1111"))
            #expect(result.content.contains("1234"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Attaches by bundle_id")
    func happyPathBundle() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-2222")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-bbb")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_attach",
            arguments: ["bundle_id": .string("com.example.app")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("dbg-bbb"))
            #expect(result.content.contains("com.example.app"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID when not provided")
    func sessionFallbackUDID() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-ccc")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(9999)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no pid or bundle_id provided")
    func missingTarget() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_attach",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(1234)]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
