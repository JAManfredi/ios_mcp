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

private let xcresultJSON = """
{
  "actions": [
    {
      "buildResult": {
        "issues": {
          "errorSummaries": [
            {"message": "Type 'Foo' does not conform to protocol 'Bar'", "documentLocationInCreatingWorkspace": {"url": "file:///src/Foo.swift", "line": 42}}
          ],
          "warningSummaries": [
            {"message": "Unused variable 'x'", "documentLocationInCreatingWorkspace": {"url": "file:///src/Bar.swift", "line": 10}}
          ]
        },
        "metrics": {
          "totalWallClockTime": 12.5,
          "totalCPUTime": 45.2
        }
      },
      "testResult": {
        "summary": {"totalCount": 10, "passedCount": 8, "failedCount": 1, "skippedCount": 1},
        "failures": [
          {"testName": "testFoo()", "message": "Expected true but got false"}
        ]
      }
    }
  ]
}
"""

@Suite("inspect_xcresult")
struct InspectXCResultToolTests {

    @Test("Inspects all sections by default")
    func allSections() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("xcresulttool") && args.contains("get") {
                return CommandResult(stdout: xcresultJSON, stderr: "", exitCode: 0)
            }
            if args.contains("xcresulttool") && args.contains("export") {
                return CommandResult(stdout: "", stderr: "", exitCode: 1)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

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
            #expect(result.content.contains("12.5s"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Inspects specific sections only")
    func specificSections() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("xcresulttool") {
                return CommandResult(stdout: xcresultJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

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
