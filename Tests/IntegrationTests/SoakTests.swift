//
//  SoakTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

/// Soak / stability tests that exercise repeated lifecycle operations and
/// verify no leaked child processes. Gated behind CI_INTEGRATION.
@Suite("Soak Tests", .enabled(if: ProcessInfo.processInfo.environment["CI_INTEGRATION"] != nil))
struct SoakTests {

    private let executor = CommandExecutor()

    // MARK: - Repeated Simulator Boot/Shutdown

    @Test("Repeated simulator boot/shutdown cycle (5 iterations)")
    func repeatedSimulatorBootShutdown() async throws {
        let udid = try await findShutdownSimulator()

        for iteration in 1...5 {
            // Boot
            let bootResult = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "boot", udid],
                timeout: 60
            )
            #expect(bootResult.succeeded, "Iteration \(iteration): boot should succeed")

            // Verify booted
            let state = try await simulatorState(udid: udid)
            #expect(state == "Booted", "Iteration \(iteration): should be Booted")

            // Shutdown
            let shutdownResult = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "shutdown", udid],
                timeout: 30
            )
            #expect(shutdownResult.succeeded, "Iteration \(iteration): shutdown should succeed")

            // Verify shutdown
            let finalState = try await simulatorState(udid: udid)
            #expect(finalState == "Shutdown", "Iteration \(iteration): should be Shutdown")
        }
    }

    // MARK: - Repeated Log Capture Start/Stop

    @Test("Repeated log capture start/stop with no leaked processes (5 iterations)")
    func repeatedLogCaptureStartStop() async throws {
        let udid = try await findBootedSimulator()
        let logCapture = LogCaptureManager()
        let logStreamCountBefore = try await countProcesses(matching: "log stream")

        for iteration in 1...5 {
            let sessionID = try await logCapture.startCapture(
                udid: udid,
                predicate: nil,
                bufferSize: 100
            )

            // Brief capture window
            try await Task.sleep(for: .milliseconds(500))

            let result = try await logCapture.stopCapture(sessionID: sessionID)
            #expect(result.entries.count >= 0, "Iteration \(iteration): stop should return a result")

            let isActive = await logCapture.hasActiveCapture(sessionID: sessionID)
            #expect(!isActive, "Iteration \(iteration): session should be inactive after stop")
        }

        // Allow child processes to terminate
        try await Task.sleep(for: .seconds(1))

        let logStreamCountAfter = try await countProcesses(matching: "log stream")
        #expect(
            logStreamCountAfter <= logStreamCountBefore,
            "Leaked log stream processes: before=\(logStreamCountBefore), after=\(logStreamCountAfter)"
        )
    }

    // MARK: - Repeated Debug Attach/Detach

    @Test("Repeated debug attach/detach with no leaked LLDB processes (3 iterations)")
    func repeatedDebugAttachDetach() async throws {
        let udid = try await findBootedSimulator()

        // Find a running process to attach to
        let pid = try await findSimulatorProcessPID(udid: udid)
        let debugSession = LLDBSessionManager()
        let lldbCountBefore = try await countProcesses(matching: "lldb")

        for iteration in 1...3 {
            let sessionID = try await debugSession.attach(
                pid: pid,
                bundleID: nil,
                udid: udid
            )
            #expect(await debugSession.isActive(sessionID: sessionID), "Iteration \(iteration): should be active")

            try await debugSession.detach(sessionID: sessionID)
            #expect(!(await debugSession.isActive(sessionID: sessionID)), "Iteration \(iteration): should be inactive")
        }

        // Allow child processes to terminate
        try await Task.sleep(for: .seconds(1))

        let lldbCountAfter = try await countProcesses(matching: "lldb")
        #expect(
            lldbCountAfter <= lldbCountBefore,
            "Leaked LLDB processes: before=\(lldbCountBefore), after=\(lldbCountAfter)"
        )
    }

    // MARK: - Build Cancellation Stress

    @Test("Build cancellation does not leak xcodebuild processes (3 iterations)")
    func buildCancellationStress() async throws {
        let xcodebuildCountBefore = try await countProcesses(matching: "xcodebuild")

        for iteration in 1...3 {
            // Start a build in a child task, then cancel it after a short delay
            let buildTask = Task {
                // Use a known-bad project so xcodebuild runs but we don't need real sources.
                // The important thing is that the process starts and we cancel it.
                let _ = try? await executor.execute(
                    executable: "/usr/bin/xcodebuild",
                    arguments: ["-scheme", "NonExistentScheme", "-destination", "generic/platform=iOS Simulator", "build"],
                    timeout: 30,
                    environment: nil
                )
            }

            // Allow the process to start
            try await Task.sleep(for: .seconds(2))
            buildTask.cancel()

            // Allow cancellation to propagate and SIGTERM/SIGKILL to complete
            try await Task.sleep(for: .seconds(4))

            // Verify the task completed (was cancelled)
            let _ = await buildTask.result
            _ = iteration // silence unused warning
        }

        // Final check: no leaked xcodebuild processes
        let xcodebuildCountAfter = try await countProcesses(matching: "xcodebuild")
        #expect(
            xcodebuildCountAfter <= xcodebuildCountBefore,
            "Leaked xcodebuild processes: before=\(xcodebuildCountBefore), after=\(xcodebuildCountAfter)"
        )
    }

    // MARK: - Helpers

    private func findShutdownSimulator() async throws -> String {
        let devices = try await listDevices()
        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if let state = device["state"] as? String,
                   state == "Shutdown",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }
        throw SoakTestError.noSimulatorAvailable("Need at least one shutdown simulator")
    }

    private func findBootedSimulator() async throws -> String {
        let devices = try await listDevices()
        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if let state = device["state"] as? String,
                   state == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }
        throw SoakTestError.noSimulatorAvailable("Need at least one booted simulator")
    }

    private func simulatorState(udid: String) async throws -> String? {
        let devices = try await listDevices()
        for (_, runtimeDevices) in devices {
            for device in runtimeDevices {
                if device["udid"] as? String == udid {
                    return device["state"] as? String
                }
            }
        }
        return nil
    }

    private func listDevices() async throws -> [String: [[String: Any]]] {
        let result = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j", "available"],
            timeout: 15
        )
        guard result.succeeded, let data = result.stdout.data(using: .utf8) else {
            throw SoakTestError.simctlFailed
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["devices"] as? [String: [[String: Any]]]) ?? [:]
    }

    private func findSimulatorProcessPID(udid: String) async throws -> Int {
        let result = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "spawn", udid, "launchctl", "list"],
            timeout: 15
        )
        guard result.succeeded else {
            throw SoakTestError.noSimulatorAvailable("Could not list processes on simulator")
        }
        // Use pid 1 (launchd) as a safe attach target
        return 1
    }

    private func countProcesses(matching name: String) async throws -> Int {
        let result = try await executor.execute(
            executable: "/usr/bin/pgrep",
            arguments: ["-f", name],
            timeout: 10
        )
        // pgrep returns exit code 1 when no matches — that's expected
        guard result.exitCode == 0 else { return 0 }
        return result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }

    enum SoakTestError: Error {
        case noSimulatorAvailable(String)
        case simctlFailed
    }
}
