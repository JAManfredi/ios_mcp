//
//  SwiftPackageResolveToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_resolve")
struct SwiftPackageResolveToolTests {

    @Test("Resolves dependencies with explicit path")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "Fetching https://github.com/example/dep.git\nResolved", stderr: "", exitCode: 0)
            }
            return simctlResult()
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: testArtifacts(), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "swift_package_resolve",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Package dependencies resolved"))
            #expect(result.content.contains("/tmp/MyPackage"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("resolve"))
        #expect(args.contains("--package-path"))
        #expect(args.contains("/tmp/MyPackage"))
    }

    @Test("Falls back to session workspace parent directory")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/tmp/MyPackage/MyPackage.xcworkspace")
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return simctlResult()
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: testArtifacts(), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "swift_package_resolve",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("/tmp/MyPackage"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("/tmp/MyPackage"))
    }

    @Test("Errors when no path available")
    func missingPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("-j") { return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0) }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: testArtifacts(), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "swift_package_resolve",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No package path"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error on command failure")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                return CommandResult(stdout: "", stderr: "Package.swift not found", exitCode: 1)
            }
            return simctlResult()
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: testArtifacts(), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "swift_package_resolve",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}

private func simctlResult() -> CommandResult {
    CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
}

private func testArtifacts() -> ArtifactStore {
    ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ios-mcp-test-\(UUID().uuidString)"))
}
