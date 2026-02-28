//
//  StopRecordingToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("stop_recording")
struct StopRecordingToolTests {

    @Test("Stops recording and returns file info")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)
        let videoRecording = MockVideoRecording()

        // Start a recording first so there's a session to stop
        _ = try await videoRecording.startRecording(udid: "AAAA-1111")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: videoRecording, navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "stop_recording",
            arguments: ["session_id": .string("mock-recording-1")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Video recording stopped"))
            #expect(result.content.contains("File path:"))
            #expect(result.content.contains("File size:"))
            #expect(!result.artifacts.isEmpty)
            #expect(result.artifacts.first?.mimeType == "video/mp4")
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id is missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "stop_recording",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors for unknown session")
    func unknownSession() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "stop_recording",
            arguments: ["session_id": .string("nonexistent")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
