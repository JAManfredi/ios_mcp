//
//  BuildRunFlowTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

/// Integration tests for discover → build → run → stop flow.
/// Requires real xcodebuild and simctl — gated behind CI_INTEGRATION.
@Suite("Build Run Flow", .enabled(if: ProcessInfo.processInfo.environment["CI_INTEGRATION"] != nil))
struct BuildRunFlowTests {

    private let executor = CommandExecutor()

    // MARK: - Build Success Produces xcresult

    @Test("Build success produces xcresult bundle")
    func buildSuccessProducesXcresult() async throws {
        // Use xcodebuild to build the ios-mcp project itself
        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-mcp-integration-\(UUID().uuidString)")
            .path

        let buildResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: [
                "xcodebuild", "build",
                "-scheme", "ios-mcp",
                "-destination", "platform=macOS",
                "-derivedDataPath", derivedData,
                "-resultBundlePath", "\(derivedData)/build.xcresult",
            ],
            timeout: 600,
            environment: nil
        )

        #expect(buildResult.succeeded, "Build should succeed for the ios-mcp project")

        // Verify xcresult exists
        let xcresultPath = "\(derivedData)/build.xcresult"
        #expect(
            FileManager.default.fileExists(atPath: xcresultPath),
            "xcresult bundle should exist at \(xcresultPath)"
        )

        // Clean up
        try? FileManager.default.removeItem(atPath: derivedData)
    }

    // MARK: - Build Failure Returns Structured Diagnostics

    @Test("Build failure returns non-zero exit code")
    func buildFailureReturnsStructuredDiagnostics() async throws {
        // Try to build a nonexistent scheme — xcodebuild should fail
        let derivedData = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-mcp-integration-\(UUID().uuidString)")
            .path

        let buildResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: [
                "xcodebuild", "build",
                "-scheme", "NonexistentScheme_\(UUID().uuidString)",
                "-destination", "platform=macOS",
                "-derivedDataPath", derivedData,
            ],
            timeout: 60,
            environment: nil
        )

        #expect(!buildResult.succeeded, "Build should fail for nonexistent scheme")
        #expect(!buildResult.stderr.isEmpty, "stderr should contain diagnostic information")

        // Clean up
        try? FileManager.default.removeItem(atPath: derivedData)
    }
}
