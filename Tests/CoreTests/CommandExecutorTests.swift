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

    @Test("Drains output larger than the pipe buffer", arguments: [false, true])
    func drainsLargeOutput(streaming: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ios-mcp-pipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let expected = String(repeating: "output line\n", count: 20_000) + "partial final line"
        try Data(expected.utf8).write(to: file)
        let executor = CommandExecutor()
        let output = StreamedOutput()
        let result: CommandResult
        if streaming {
            result = try await executor.executeStreaming(executable: "/bin/cat", arguments: [file.path], timeout: 10) {
                await output.append($0)
            }
            #expect(await output.text == expected)
        } else {
            result = try await executor.execute(executable: "/bin/cat", arguments: [file.path], timeout: 10)
        }
        #expect(result.stdout == expected)
        #expect(result.succeeded)
        let failure: CommandResult
        let missing = file.path + ".missing"
        if streaming {
            failure = try await executor.executeStreaming(executable: "/bin/cat", arguments: [missing]) { _ in }
        } else {
            failure = try await executor.execute(executable: "/bin/cat", arguments: [missing])
        }
        #expect(!failure.succeeded)
        #expect(failure.stdout.isEmpty)
        #expect(failure.stderr.contains(missing))
    }

    @Test("Launch failures release pipe readers and subsequent commands work", arguments: [false, true])
    func launchFailureDoesNotLeakReaders(streaming: Bool) async throws {
        let executor = CommandExecutor()
        do {
            if streaming {
                _ = try await executor.executeStreaming(executable: "/__ios_mcp_missing_executable__") { _ in }
            } else {
                _ = try await executor.execute(executable: "/__ios_mcp_missing_executable__")
            }
            Issue.record("Expected launch failure")
        } catch let error as ToolError { #expect(error.code == .commandFailed) }
        let result = try await executor.execute(executable: "/bin/echo", arguments: ["after failure"])
        #expect(result.stdout == "after failure\n")
    }

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
        _ = try await task.value
        let elapsed = ContinuousClock.now - start

        // The task should complete quickly after cancellation (not wait 60s).
        // Exit code is not checked — Process.terminationStatus is unreliable for
        // signal-killed processes (WEXITSTATUS reads a different byte than the signal number).
        #expect(elapsed < .seconds(2))
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

private actor StreamedOutput {
    private(set) var text = ""
    func append(_ chunk: String) { text += chunk }
}
