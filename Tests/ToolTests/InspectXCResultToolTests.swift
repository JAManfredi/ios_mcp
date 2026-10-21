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
    {"testName": "testFoo()", "targetName": "MyAppTests", "failureText": "Expected true but got false", "testIdentifier": "MyAppTests/testFoo()"}
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
            if args.contains("xccov") {
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
            #expect(result.content.contains("testFoo(): Expected true but got false"))
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

    @Test("Reads coverage from xccov")
    func coverageFromXccov() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = AllCallCapture()
        let xccovJSON = """
        {"coveredLines": 50, "executableLines": 100, "lineCoverage": 0.5, "targets": [
          {"name": "MyApp.app", "lineCoverage": 0.5, "files": [
            {"name": "Good.swift", "lineCoverage": 0.9},
            {"name": "Bad.swift", "lineCoverage": 0.1}
          ]}
        ]}
        """
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            if args.contains("xccov") {
                return CommandResult(stdout: xccovJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "inspect_xcresult",
            arguments: ["path": .string("/tmp/test.xcresult"), "sections": .string("coverage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Overall: 50.0% (50/100 lines)"))
            #expect(result.content.contains("MyApp.app: 50.0%"))
            let bad = result.content.range(of: "Bad.swift")
            let good = result.content.range(of: "Good.swift")
            #expect(bad != nil && good != nil && bad!.lowerBound < good!.lowerBound)
        } else {
            Issue.record("Expected success response")
        }

        let calls = await capture.allArgs
        #expect(calls.contains(["xccov", "view", "--report", "--json", "/tmp/test.xcresult"]))
        #expect(!calls.contains { $0.contains("--legacy") })
    }

    @Test("Exports attachments with the Xcode 16+ subcommand")
    func attachmentsExport() async throws {
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let artifacts = ArtifactStore(baseDirectory: storeDirectory, ttl: 0)
        let executor = MockCommandExecutor { _, args in
            if args.starts(with: ["xcresulttool", "export", "attachments"]),
               let i = args.firstIndex(of: "--output-path") {
                await capture.capture(args)
                let dir = URL(fileURLWithPath: args[i + 1])
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data([0x89, 0x50]).write(to: dir.appendingPathComponent("ABC.png"))
                let manifest = """
                [{"testIdentifier": "MyAppTests/testFoo()", "attachments": [
                  {"exportedFileName": "ABC.png", "suggestedHumanReadableName": "Screenshot", "isAssociatedWithFailure": true}
                ]}]
                """
                try Data(manifest.utf8).write(to: dir.appendingPathComponent("manifest.json"))
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerInspectXCResultTool(with: registry, executor: executor, artifacts: artifacts)

        let response = try await registry.callTool(
            name: "inspect_xcresult",
            arguments: ["path": .string("/tmp/test.xcresult"), "sections": .string("attachments")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Exported 1 files (1 images)"))
            #expect(result.content.contains("ABC.png — MyAppTests/testFoo() · Screenshot · failure"))
            let ref = try #require(result.artifacts.first)
            #expect(try Data(contentsOf: URL(fileURLWithPath: ref.path)) == Data([0x89, 0x50]))
            #expect(result.content.contains(ref.path))
            #expect(!result.inlineArtifacts)
            let args = await capture.lastArgs
            let index = try #require(args.firstIndex(of: "--output-path"))
            #expect(!FileManager.default.fileExists(atPath: args[index + 1]))
            #expect(!result.content.contains(args[index + 1]))
            await artifacts.evictExpired()
            #expect(!FileManager.default.fileExists(atPath: ref.path))
            #expect(await artifacts.totalSize() == 0)
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Removes partial exports on failure, timeout, and cancellation", arguments: ["failure", "timeout", "cancelled"])
    func failedExportCleanup(failure: String) async throws {
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let artifacts = ArtifactStore(baseDirectory: storeDirectory)
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            let index = try #require(args.firstIndex(of: "--output-path"))
            let dir = URL(fileURLWithPath: args[index + 1])
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: dir.appendingPathComponent("partial.mp4"))
            if failure == "cancelled" { throw CancellationError() }
            if failure == "timeout" { throw ToolError(code: .timeout, message: "Timed out") }
            return CommandResult(stdout: "", stderr: "Export failed", exitCode: 1)
        }
        await registerInspectXCResultTool(with: registry, executor: executor, artifacts: artifacts)
        let response = try await registry.callTool(name: "inspect_xcresult", arguments: [
            "path": .string("/tmp/test.xcresult"), "sections": .string("attachments"),
        ])
        guard case .success(let result) = response else { Issue.record("Expected partial inspection"); return }
        #expect(result.content.contains("Attachment export not available"))
        #expect(result.artifacts.isEmpty)
        let args = await capture.lastArgs
        let index = try #require(args.firstIndex(of: "--output-path"))
        #expect(!FileManager.default.fileExists(atPath: args[index + 1]))
        #expect(await artifacts.totalSize() == 0)
    }

    @Test("Retains only the image limit and removes unretained exports")
    func attachmentLimit() async throws {
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let artifacts = ArtifactStore(baseDirectory: storeDirectory)
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            let index = try #require(args.firstIndex(of: "--output-path"))
            let dir = URL(fileURLWithPath: args[index + 1])
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for number in 0..<12 {
                try Data([1, 2, 3]).write(to: dir.appendingPathComponent("image-\(number).png"))
            }
            try Data([4, 5, 6]).write(to: dir.appendingPathComponent("recording.mp4"))
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        await registerInspectXCResultTool(with: registry, executor: executor, artifacts: artifacts)
        let response = try await registry.callTool(name: "inspect_xcresult", arguments: [
            "path": .string("/tmp/test.xcresult"), "sections": .string("attachments"),
        ])
        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.artifacts.count == 10)
        #expect(await artifacts.totalSize() == 30)
        for ref in result.artifacts { #expect(FileManager.default.fileExists(atPath: ref.path)) }
        let args = await capture.lastArgs
        let index = try #require(args.firstIndex(of: "--output-path"))
        #expect(!FileManager.default.fileExists(atPath: args[index + 1]))
    }

    @Test("Reports storage failures and still cleans up the export")
    func attachmentStorageFailure() async throws {
        let registry = ToolRegistry()
        let capture = ArgCapture()
        // A regular file cannot be used as the artifact store directory.
        let storePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")
        try Data([0]).write(to: storePath)
        defer { try? FileManager.default.removeItem(at: storePath) }
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            let index = try #require(args.firstIndex(of: "--output-path"))
            let dir = URL(fileURLWithPath: args[index + 1])
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: dir.appendingPathComponent("image.png"))
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        await registerInspectXCResultTool(with: registry, executor: executor, artifacts: ArtifactStore(baseDirectory: storePath))
        let response = try await registry.callTool(name: "inspect_xcresult", arguments: [
            "path": .string("/tmp/test.xcresult"), "sections": .string("attachments"),
        ])
        guard case .success(let result) = response else { Issue.record("Expected partial inspection"); return }
        #expect(result.artifacts.isEmpty)
        #expect(result.content.contains("Could not retain image.png"))
        #expect(!result.content.contains("Stored at:"))
        let args = await capture.lastArgs
        let index = try #require(args.firstIndex(of: "--output-path"))
        #expect(!FileManager.default.fileExists(atPath: args[index + 1]))
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
