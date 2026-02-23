//
//  CommandExecutorTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("CommandExecutor")
struct CommandExecutorTests {

    @Test("Executes successfully and returns stdout")
    func executesSuccessfully() async throws {
        let executor = CommandExecutor()
        let result = try await executor.execute(
            executable: "/bin/echo",
            arguments: ["hello"],
            timeout: 10,
            environment: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.succeeded)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("Reports non-zero exit code")
    func reportsNonZeroExitCode() async throws {
        let executor = CommandExecutor()
        let result = try await executor.execute(
            executable: "/usr/bin/false",
            arguments: [],
            timeout: 10,
            environment: nil
        )

        #expect(result.exitCode != 0)
        #expect(!result.succeeded)
    }

    @Test("Terminates process on task cancellation")
    func terminatesOnCancellation() async throws {
        let executor = CommandExecutor()

        let task = Task {
            try await executor.execute(
                executable: "/bin/sleep",
                arguments: ["60"],
                timeout: nil,
                environment: nil
            )
        }

        // Give the process a moment to start
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let start = ContinuousClock.now
        let result = try await task.value
        let elapsed = ContinuousClock.now - start

        // The task should complete quickly after cancellation (not wait 60s)
        #expect(elapsed < .seconds(2))
        #expect(result.exitCode != 0)
    }

    @Test("Timeout kills child process tree")
    func timeoutKillsProcessTree() async throws {
        let executor = CommandExecutor()

        // Spawn a shell that forks a background child, then sleeps.
        // The child writes its PID to a temp file so we can check if it was killed.
        let pidFile = NSTemporaryDirectory() + "ios-mcp-test-child-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: pidFile) }

        // Script: fork a background sleep, record its PID, then sleep the parent
        let script = """
        /bin/bash -c 'sleep 300 & echo $! > \(pidFile); sleep 300'
        """

        let result = try await executor.execute(
            executable: "/bin/bash",
            arguments: ["-c", script],
            timeout: 1,
            environment: nil
        )

        // Parent was killed by timeout
        #expect(result.exitCode != 0)

        // Give SIGKILL grace period time to fire
        try await Task.sleep(for: .seconds(4))

        // Read the child PID and verify it's no longer running
        if let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let childPID = Int32(pidString) {
            let isAlive = kill(childPID, 0) == 0
            #expect(!isAlive, "Child process \(childPID) should have been killed with the process group")
        }
    }
}
