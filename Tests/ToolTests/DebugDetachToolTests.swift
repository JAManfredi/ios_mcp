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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator())

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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

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

    @Test("Releases concurrency lock after detach")
    func releasesLockOnDetach() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-lock")
        let concurrency = ConcurrencyPolicy()

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator())

        // Attach — acquires a lock
        let attachResponse = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(1234), "udid": .string("SIM-1111")]
        )
        guard case .success = attachResponse else {
            Issue.record("Expected successful attach")
            return
        }

        // Verify lock is held
        let lockKey = "lldb:1234"
        let isLocked = await concurrency.isLocked(key: lockKey)
        #expect(isLocked, "Lock should be held after attach")

        // Detach — should release the lock
        let detachResponse = try await registry.callTool(
            name: "debug_detach",
            arguments: ["session_id": .string("dbg-lock")]
        )
        guard case .success = detachResponse else {
            Issue.record("Expected successful detach")
            return
        }

        // Verify lock is released
        let isStillLocked = await concurrency.isLocked(key: lockKey)
        #expect(!isStillLocked, "Lock should be released after detach")
    }

    @Test("Re-attach succeeds after detach releases lock")
    func reattachAfterDetach() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockDebug = MockDebugSession(nextSessionID: "dbg-reattach1")
        let concurrency = ConcurrencyPolicy()

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: mockDebug, validator: testValidator())

        // Attach
        _ = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(5678), "udid": .string("SIM-1111")]
        )

        // Detach
        _ = try await registry.callTool(
            name: "debug_detach",
            arguments: ["session_id": .string("dbg-reattach1")]
        )

        // Re-attach with same PID should succeed (lock released)
        await mockDebug.setNextSessionID("dbg-reattach2")
        let reattach = try await registry.callTool(
            name: "debug_attach",
            arguments: ["pid": .int(5678), "udid": .string("SIM-1111")]
        )
        if case .success(let result) = reattach {
            #expect(result.content.contains("dbg-reattach2"))
        } else {
            Issue.record("Expected re-attach to succeed after detach released the lock")
        }
    }

    @Test("Errors when session_id is unknown")
    func unknownSession() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

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
