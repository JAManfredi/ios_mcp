//
//  SimulatorLifecycleTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

/// Integration tests for simulator boot/shutdown/erase lifecycle.
/// Requires real simctl — gated behind CI_INTEGRATION environment variable.
@Suite("Simulator Lifecycle", .enabled(if: ProcessInfo.processInfo.environment["CI_INTEGRATION"] != nil))
struct SimulatorLifecycleTests {

    private let executor = CommandExecutor()

    // MARK: - Boot and Shutdown Cycle

    @Test("Boot and shutdown a simulator")
    func bootAndShutdownCycle() async throws {
        // Find the first available shutdown simulator
        let listResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j", "available"],
            timeout: 15,
            environment: nil
        )
        #expect(listResult.succeeded, "simctl list devices should succeed")

        let data = try #require(listResult.stdout.data(using: .utf8))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let devices = try #require(json["devices"] as? [String: [[String: Any]]])

        // Find a shutdown device to test with
        var targetUDID: String?
        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if let state = device["state"] as? String,
                   state == "Shutdown",
                   let udid = device["udid"] as? String {
                    targetUDID = udid
                    break
                }
            }
            if targetUDID != nil { break }
        }

        let udid = try #require(targetUDID, "Need at least one shutdown simulator")

        // Boot
        let bootResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "boot", udid],
            timeout: 60,
            environment: nil
        )
        #expect(bootResult.succeeded, "simctl boot should succeed")

        // Verify booted state
        let verifyResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j"],
            timeout: 15,
            environment: nil
        )
        let verifyData = try #require(verifyResult.stdout.data(using: .utf8))
        let verifyJSON = try #require(
            try JSONSerialization.jsonObject(with: verifyData) as? [String: Any]
        )
        let verifyDevices = try #require(verifyJSON["devices"] as? [String: [[String: Any]]])

        var bootedState: String?
        for (_, runtimeDevices) in verifyDevices {
            for device in runtimeDevices {
                if device["udid"] as? String == udid {
                    bootedState = device["state"] as? String
                    break
                }
            }
            if bootedState != nil { break }
        }
        #expect(bootedState == "Booted", "Simulator should be in Booted state")

        // Shutdown
        let shutdownResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "shutdown", udid],
            timeout: 30,
            environment: nil
        )
        #expect(shutdownResult.succeeded, "simctl shutdown should succeed")

        // Verify shutdown state
        let finalResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j"],
            timeout: 15,
            environment: nil
        )
        let finalData = try #require(finalResult.stdout.data(using: .utf8))
        let finalJSON = try #require(
            try JSONSerialization.jsonObject(with: finalData) as? [String: Any]
        )
        let finalDevices = try #require(finalJSON["devices"] as? [String: [[String: Any]]])

        var finalState: String?
        for (_, runtimeDevices) in finalDevices {
            for device in runtimeDevices {
                if device["udid"] as? String == udid {
                    finalState = device["state"] as? String
                    break
                }
            }
            if finalState != nil { break }
        }
        #expect(finalState == "Shutdown", "Simulator should be back in Shutdown state")
    }

    // MARK: - Erase Requires Shutdown

    @Test("Erase fails on booted simulator")
    func eraseRequiresShutdown() async throws {
        // Find or boot a simulator
        let listResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j", "available"],
            timeout: 15,
            environment: nil
        )
        let data = try #require(listResult.stdout.data(using: .utf8))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let devices = try #require(json["devices"] as? [String: [[String: Any]]])

        // Find a shutdown device, boot it, then try to erase
        var targetUDID: String?
        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if let state = device["state"] as? String,
                   state == "Shutdown",
                   let udid = device["udid"] as? String {
                    targetUDID = udid
                    break
                }
            }
            if targetUDID != nil { break }
        }

        let udid = try #require(targetUDID, "Need at least one shutdown simulator")

        // Boot first
        let bootResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "boot", udid],
            timeout: 60,
            environment: nil
        )
        #expect(bootResult.succeeded)

        // Attempt erase on booted sim — should fail
        let eraseResult = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "erase", udid],
            timeout: 60,
            environment: nil
        )
        #expect(!eraseResult.succeeded, "Erase should fail on a booted simulator")

        // Clean up: shutdown
        _ = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "shutdown", udid],
            timeout: 30,
            environment: nil
        )
    }
}
