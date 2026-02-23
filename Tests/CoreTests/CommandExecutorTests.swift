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
}
