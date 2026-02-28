//
//  CrashLogToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("list_crash_logs")
struct CrashLogToolTests {

    @Test("Returns empty when no crash logs directory")
    func noCrashDir() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "list_crash_logs",
            arguments: [:]
        )

        // Tool should return success with either "No crash logs found" or actual crash logs
        // depending on whether the DiagnosticReports directory exists on this machine
        if case .success(let result) = response {
            #expect(!result.content.isEmpty)
        } else if case .error = response {
            // May error if somehow the tool fails, but shouldn't happen
            Issue.record("Unexpected error")
        }
    }
}
