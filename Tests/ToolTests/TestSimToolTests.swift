//
//  TestSimToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("test_simulator")
struct TestSimToolTests {

    private let testResultJSON = """
    {
      "actions": [
        {
          "testResult": {
            "summary": {
              "totalCount": 10,
              "passedCount": 8,
              "failedCount": 1,
              "skippedCount": 1
            },
            "failures": [
              {
                "testName": "MyTests/testBroken",
                "message": "Expected true, got false"
              }
            ]
          },
          "buildResult": {
            "issues": {
              "errorSummaries": [],
              "warningSummaries": []
            }
          }
        }
      ]
    }
    """

    @Test("Runs tests and returns results")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("test") {
                await capture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: self.testResultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "test_simulator", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Tests passed"))
            #expect(result.content.contains("Elapsed:"))
            #expect(result.content.contains("8 passed"))
            #expect(result.content.contains("1 failed"))
            #expect(result.content.contains("1 skipped"))
            #expect(result.content.contains("xcresult:"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("test"))
        #expect(capturedArgs.contains("-scheme"))
        #expect(capturedArgs.contains("MyApp"))
    }

    @Test("Passes only_testing and skip_testing args")
    func testFiltering() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("test") {
                await capture.capture(args)
            }
            return CommandResult(stdout: self.testResultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        _ = try await registry.callTool(
            name: "test_simulator",
            arguments: [
                "only_testing": .string("MyTests/testFoo,MyTests/testBar"),
                "skip_testing": .string("MyTests/testSlow"),
                "test_plan": .string("CI"),
            ]
        )

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-only-testing:MyTests/testFoo"))
        #expect(capturedArgs.contains("-only-testing:MyTests/testBar"))
        #expect(capturedArgs.contains("-skip-testing:MyTests/testSlow"))
        #expect(capturedArgs.contains("-testPlan"))
        #expect(capturedArgs.contains("CI"))
    }

    @Test("Returns resource busy when lock held")
    func resourceBusy() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let concurrency = ConcurrencyPolicy()
        let executor = MockCommandExecutor.succeedingWith("")

        _ = await concurrency.acquire(key: "build:/path/to/App.xcworkspace", owner: "other_build")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "test_simulator", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .resourceBusy)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns failing test names on failure")
    func testFailure() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("test") {
                return CommandResult(stdout: "", stderr: "Testing failed", exitCode: 65)
            }
            return CommandResult(stdout: self.testResultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "test_simulator", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
            #expect(error.message.contains("Tests failed"))
            #expect(error.message.contains("Elapsed:"))
            #expect(error.message.contains("MyTests/testBroken"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
