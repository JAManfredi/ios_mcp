//
//  SwiftPackageUpdateToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_update")
struct SwiftPackageUpdateToolTests {

    @Test("Updates dependencies with explicit path")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "Updated https://github.com/example/dep.git", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "swift_package_update",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Package dependencies updated"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("update"))
        #expect(args.contains("--package-path"))
    }
}
