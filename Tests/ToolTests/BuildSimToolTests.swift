//
//  BuildSimToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("build_sim")
struct BuildSimToolTests {

    private let xcresultJSON = """
    {
      "actions": [
        {
          "buildResult": {
            "issues": {
              "errorSummaries": [],
              "warningSummaries": [
                { "message": "Unused variable 'x'" }
              ]
            }
          }
        }
      ]
    }
    """

    @Test("Builds successfully with diagnostics")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                await capture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            // xcresulttool response
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Build succeeded"))
            #expect(result.content.contains("Errors: 0"))
            #expect(result.content.contains("Warnings: 1"))
            #expect(result.content.contains("xcresult:"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-workspace"))
        #expect(capturedArgs.contains("/path/to/App.xcworkspace"))
        #expect(capturedArgs.contains("-scheme"))
        #expect(capturedArgs.contains("MyApp"))
        #expect(capturedArgs.contains("build"))
    }

    @Test("Falls back to session defaults")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.project, value: "/path/to/App.xcodeproj")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")
        await session.set(.configuration, value: "Release")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                await capture.capture(args)
            }
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        _ = try await registry.callTool(name: "build_sim", arguments: [:])

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-project"))
        #expect(capturedArgs.contains("/path/to/App.xcodeproj"))
        #expect(capturedArgs.contains("-configuration"))
        #expect(capturedArgs.contains("Release"))
    }

    @Test("Errors when no scheme available")
    func missingScheme() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No scheme"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no workspace or project available")
    func missingWorkspace() async throws {
        let session = SessionStore()
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No workspace or project"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when xcodebuild fails")
    func buildFailure() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let errorJSON = """
        {
          "actions": [
            {
              "buildResult": {
                "issues": {
                  "errorSummaries": [
                    { "message": "Cannot find 'Foo' in scope" }
                  ],
                  "warningSummaries": []
                }
              }
            }
          ]
        }
        """

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "Build failed", exitCode: 65)
            }
            return CommandResult(stdout: errorJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
            #expect(error.message.contains("Build failed"))
        } else {
            Issue.record("Expected error response")
        }
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "build_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .resourceBusy)
        } else {
            Issue.record("Expected error response")
        }
    }
}
