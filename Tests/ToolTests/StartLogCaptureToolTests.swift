//
//  StartLogCaptureToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("start_log_capture")
struct StartLogCaptureToolTests {

    @Test("Returns session ID on success")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockCapture = MockLogCapture(nextID: "test-session-abc")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: mockCapture)

        let response = try await registry.callTool(
            name: "start_log_capture",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Log capture started"))
            #expect(result.content.contains("test-session-abc"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")
        let mockCapture = MockLogCapture(nextID: "sess-123")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: mockCapture)

        let response = try await registry.callTool(name: "start_log_capture", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture())

        let response = try await registry.callTool(name: "start_log_capture", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Includes filter in response when provided")
    func withFilter() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture())

        let response = try await registry.callTool(
            name: "start_log_capture",
            arguments: [
                "subsystem": .string("com.example"),
                "category": .string("network"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Filter:"))
            #expect(result.content.contains("com.example"))
            #expect(result.content.contains("network"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
