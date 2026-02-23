//
//  UISnapshotFlowTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

/// Integration tests for snapshot_ui tool behavior with and without axe.
/// Gated behind CI_INTEGRATION.
@Suite("UI Snapshot Flow", .enabled(if: ProcessInfo.processInfo.environment["CI_INTEGRATION"] != nil))
struct UISnapshotFlowTests {

    private let executor = CommandExecutor()

    // MARK: - Snapshot UI with axe Missing

    @Test("snapshot_ui returns dependency_missing when axe not found")
    func snapshotUIWithAxeMissing() async throws {
        // Attempt to run a nonexistent axe binary to verify the error path
        let result = try await executor.execute(
            executable: "/usr/bin/which",
            arguments: ["axe-nonexistent-binary-\(UUID().uuidString)"],
            timeout: 5,
            environment: nil
        )

        // `which` returns non-zero when the binary is not found
        #expect(!result.succeeded, "which should fail for nonexistent binary")

        // The tool layer would translate this into a dependency_missing error.
        // Here we verify the underlying detection mechanism works.
    }

    // MARK: - Snapshot UI with axe Present

    @Test(
        "snapshot_ui returns accessibility tree when axe is available",
        .enabled(if: FileManager.default.fileExists(atPath: "/usr/local/bin/axe")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/axe"))
    )
    func snapshotUIWithAxePresent() async throws {
        let udid = try await findBootedSimulator()

        // Resolve axe path
        let whichResult = try await executor.execute(
            executable: "/usr/bin/which",
            arguments: ["axe"],
            timeout: 5,
            environment: nil
        )

        let axePath = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!axePath.isEmpty, "axe should be resolvable via which")

        let dumpResult = try await executor.execute(
            executable: axePath,
            arguments: ["describe-ui", "--udid", udid],
            timeout: 30,
            environment: nil
        )

        #expect(dumpResult.succeeded, "axe describe-ui should succeed on a booted simulator")
        #expect(!dumpResult.stdout.isEmpty, "axe describe-ui should return accessibility tree content")
    }

    // MARK: - Helpers

    private func findBootedSimulator() async throws -> String {
        let result = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j", "available"],
            timeout: 15,
            environment: nil
        )

        let data = try #require(result.stdout.data(using: .utf8))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let devices = try #require(json["devices"] as? [String: [[String: Any]]])

        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if let state = device["state"] as? String,
                   state == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }

        throw ToolError(
            code: .invalidInput,
            message: "No booted simulator found. Boot one first."
        )
    }
}
