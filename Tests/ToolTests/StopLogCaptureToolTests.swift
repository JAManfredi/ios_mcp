//
//  StopLogCaptureToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("stop_log_capture")
struct StopLogCaptureToolTests {

    @Test("Returns formatted entries on success")
    func happyPath() async throws {
        let entries = [
            LogEntry(
                timestamp: "2024-01-15 10:30:00",
                processName: "MyApp",
                pid: 12345,
                subsystem: "com.example",
                category: "network",
                level: "Default",
                message: "Request completed"
            ),
            LogEntry(
                timestamp: "2024-01-15 10:30:01",
                processName: "MyApp",
                pid: 12345,
                subsystem: "com.example",
                category: "ui",
                level: "Error",
                message: "View failed to load"
            ),
        ]
        let cannedResult = LogCaptureResult(
            entries: entries,
            droppedEntryCount: 0,
            totalEntriesReceived: 2
        )
        let mockCapture = MockLogCapture(nextID: "sess-1", cannedResult: cannedResult)

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: mockCapture, debugSession: MockDebugSession())

        // Start first so the session exists
        _ = try await registry.callTool(
            name: "start_log_capture",
            arguments: ["udid": .string("AAAA-1111")]
        )

        let response = try await registry.callTool(
            name: "stop_log_capture",
            arguments: ["session_id": .string("sess-1")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Log capture stopped"))
            #expect(result.content.contains("Entries returned: 2"))
            #expect(result.content.contains("Request completed"))
            #expect(result.content.contains("View failed to load"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Returns error for unknown session ID")
    func unknownSession() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(
            name: "stop_log_capture",
            arguments: ["session_id": .string("nonexistent-id")]
        )

        if case .error(let error) = response {
            #expect(error.message.contains("Unknown log capture session"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Reports dropped entries in response")
    func droppedEntries() async throws {
        let cannedResult = LogCaptureResult(
            entries: [
                LogEntry(
                    timestamp: "2024-01-15",
                    processName: "MyApp",
                    pid: 1,
                    subsystem: "",
                    category: "",
                    level: "Default",
                    message: "Latest entry"
                ),
            ],
            droppedEntryCount: 500,
            totalEntriesReceived: 501
        )
        let mockCapture = MockLogCapture(nextID: "sess-1", cannedResult: cannedResult)

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: mockCapture, debugSession: MockDebugSession())

        _ = try await registry.callTool(
            name: "start_log_capture",
            arguments: ["udid": .string("AAAA-1111")]
        )

        let response = try await registry.callTool(
            name: "stop_log_capture",
            arguments: ["session_id": .string("sess-1")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Dropped entries (buffer overflow): 500"))
            #expect(result.content.contains("Total entries received: 501"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when session_id missing")
    func missingSessionID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession())

        let response = try await registry.callTool(name: "stop_log_capture", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("session_id"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Limits entries with max_entries")
    func maxEntries() async throws {
        let entries = (0..<10).map { i in
            LogEntry(
                timestamp: "2024-01-15",
                processName: "MyApp",
                pid: 1,
                subsystem: "",
                category: "",
                level: "Default",
                message: "Entry \(i)"
            )
        }
        let cannedResult = LogCaptureResult(
            entries: entries,
            droppedEntryCount: 0,
            totalEntriesReceived: 10
        )
        let mockCapture = MockLogCapture(nextID: "sess-1", cannedResult: cannedResult)

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: mockCapture, debugSession: MockDebugSession())

        _ = try await registry.callTool(
            name: "start_log_capture",
            arguments: ["udid": .string("AAAA-1111")]
        )

        let response = try await registry.callTool(
            name: "stop_log_capture",
            arguments: [
                "session_id": .string("sess-1"),
                "max_entries": .int(3),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Entries returned: 3"))
            // Should contain the last 3 entries (7, 8, 9)
            #expect(result.content.contains("Entry 7"))
            #expect(result.content.contains("Entry 8"))
            #expect(result.content.contains("Entry 9"))
            #expect(!result.content.contains("Entry 0"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
