//
//  SwiftPackageCleanToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_clean")
struct SwiftPackageCleanToolTests {

    @Test("Cleans package with explicit path")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_clean",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Package build artifacts cleaned"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("clean"))
    }
}
