//
//  SwiftPackageDumpToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_dump")
struct SwiftPackageDumpToolTests {

    @Test("Dumps package manifest as JSON")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let manifestJSON = """
        {"name":"MyPackage","targets":[{"name":"MyTarget","type":"regular"}]}
        """
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                return CommandResult(stdout: manifestJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_dump",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Package manifest"))
            #expect(result.content.contains("MyTarget"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session project parent")
    func projectFallback() async throws {
        let session = SessionStore()
        await session.set(.project, value: "/tmp/MyPackage/MyPackage.xcodeproj")
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "{}", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_dump",
            arguments: [:]
        )

        if case .success = response {
            let args = await capture.lastArgs
            #expect(args.contains("/tmp/MyPackage"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
