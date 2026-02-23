//
//  LogCaptureLifecycleTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

/// Integration tests for log capture start → capture → stop → verify cycle.
/// Requires a booted simulator — gated behind CI_INTEGRATION.
@Suite("Log Capture Lifecycle", .enabled(if: ProcessInfo.processInfo.environment["CI_INTEGRATION"] != nil))
struct LogCaptureLifecycleTests {

    private let manager = LogCaptureManager()
    private let executor = CommandExecutor()

    // MARK: - Start/Stop Capture Cycle

    @Test("Start and stop log capture returns result structure")
    func startStopCaptureCycle() async throws {
        // Find a booted simulator
        let udid = try await findBootedSimulator()

        // Start capture with a small buffer
        let sessionID = try await manager.startCapture(
            udid: udid,
            predicate: nil,
            bufferSize: 1000
        )
        #expect(!sessionID.isEmpty, "Session ID should be non-empty")

        // Verify the session is active
        let isActive = await manager.hasActiveCapture(sessionID: sessionID)
        #expect(isActive, "Capture session should be active after start")

        // Wait briefly for some log entries to accumulate
        try await Task.sleep(for: .seconds(2))

        // Stop and retrieve
        let result = try await manager.stopCapture(sessionID: sessionID)

        // Verify result structure
        #expect(result.totalEntriesReceived >= 0, "Should have a non-negative entry count")
        #expect(result.droppedEntryCount >= 0, "Should have a non-negative dropped count")

        // Verify session is no longer active
        let isStillActive = await manager.hasActiveCapture(sessionID: sessionID)
        #expect(!isStillActive, "Capture session should be inactive after stop")
    }

    // MARK: - Buffer Overflow

    @Test("Buffer overflow produces nonzero droppedEntryCount")
    func bufferOverflow() async throws {
        let udid = try await findBootedSimulator()

        // Use a tiny buffer to force overflow from simulator log volume
        let sessionID = try await manager.startCapture(
            udid: udid,
            predicate: nil,
            bufferSize: 10
        )

        // Wait for enough log entries to exceed the small buffer
        try await Task.sleep(for: .seconds(5))

        let result = try await manager.stopCapture(sessionID: sessionID)

        #expect(result.totalEntriesReceived > 10, "Expected more entries received than buffer capacity")
        #expect(result.droppedEntryCount > 0, "Expected nonzero dropped count with tiny buffer")
        #expect(result.entries.count <= 10, "Entries in buffer should not exceed capacity")
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
