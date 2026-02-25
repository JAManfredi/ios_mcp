//
//  SwiftPackageShowDepsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_show_deps")
struct SwiftPackageShowDepsToolTests {

    @Test("Shows dependencies in JSON format")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let depsJSON = """
        {"name":"MyPackage","dependencies":[{"name":"swift-log","url":"https://github.com/apple/swift-log.git"}]}
        """
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                return CommandResult(stdout: depsJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_show_deps",
            arguments: ["path": .string("/tmp/MyPackage")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Package dependency tree"))
            #expect(result.content.contains("swift-log"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
