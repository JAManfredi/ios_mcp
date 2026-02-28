//
//  InspectXCResultToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

private let buildResultsJSON = """
{
  "status": "succeeded",
  "startTime": 1000.0,
  "endTime": 1012.5,
  "errorCount": 1,
  "errors": [
    {"message": "Type 'Foo' does not conform to protocol 'Bar'", "issueType": "Semantic Issue"}
  ],
  "warningCount": 1,
  "warnings": [
    {"message": "Unused variable 'x'"}
  ],
  "analyzerWarningCount": 0,
  "analyzerWarnings": [],
  "destination": {
    "deviceName": "iPhone 16 Pro",
    "osVersion": "18.0"
  }
}
"""

private let testSummaryJSON = """
{
  "totalTestCount": 10,
  "passedTests": 8,
  "failedTests": 1,
  "skippedTests": 1,
  "result": "failed",
  "title": "Test - MyApp",
  "testFailures": [
    {"testName": "testFoo()", "message": "Expected true but got false"}
  ],
  "startTime": 1000.0,
  "finishTime": 1012.5,
  "devicesAndConfigurations": [],
  "statistics": [],
  "topInsights": [],
  "expectedFailures": 0
}
"""

@Suite("inspect_xcresult")
struct InspectXCResultToolTests {

    @Test("Inspects all sections by default")
    func allSections() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("build-results") {
                return CommandResult(stdout: buildResultsJSON, stderr: "", exitCode: 0)
            }
            if args.contains("test-results") && args.contains("summary") {
                return CommandResult(stdout: testSummaryJSON, stderr: "", exitCode: 0)
            }
            if args.contains("codeCoverage") {
                return CommandResult(stdout: "", stderr: "not available", exitCode: 1)
            }
            if args.contains("export") {
                return CommandResult(stdout: "", stderr: "", exitCode: 1)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "inspect_xcresult",
            arguments: ["path": .string("/tmp/test.xcresult")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("## Diagnostics"))
            #expect(result.content.contains("Errors (1)"))
            #expect(result.content.contains("Type 'Foo'"))
            #expect(result.content.contains("Warnings (1)"))
            #expect(result.content.contains("## Test Results"))
            #expect(result.content.contains("Total: 10"))
            #expect(result.content.contains("Failed: 1"))
            #expect(result.content.contains("testFoo()"))
            #expect(result.content.contains("## Build Timeline"))
            #expect(result.content.contains("Duration: 12.5s"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Inspects specific sections only")
    func specificSections() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("build-results") {
                return CommandResult(stdout: buildResultsJSON, stderr: "", exitCode: 0)
            }
            if args.contains("test-results") && args.contains("summary") {
                return CommandResult(stdout: testSummaryJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "inspect_xcresult",
            arguments: [
                "path": .string("/tmp/test.xcresult"),
                "sections": .string("diagnostics,tests"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("## Diagnostics"))
            #expect(result.content.contains("## Test Results"))
            #expect(!result.content.contains("## Code Coverage"))
            #expect(!result.content.contains("## Attachments"))
            #expect(!result.content.contains("## Build Timeline"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when path is missing")
    func missingPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "inspect_xcresult",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
