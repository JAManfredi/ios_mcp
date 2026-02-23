//
//  CommandExecutor.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Logging

/// Protocol for executing CLI commands, enabling mock-based testing.
public protocol CommandExecuting: Sendable {
    func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval?,
        environment: [String: String]?
    ) async throws -> CommandResult
}

/// Async wrapper around `Process` for executing CLI commands with arg arrays.
/// Never uses shell execution — always passes arguments directly.
/// Applies `Redactor.redact()` to stdout/stderr before returning.
/// Supports Swift Concurrency cancellation — cancelling the Task terminates the child process.
public struct CommandExecutor: CommandExecuting, Sendable {
    private let logger = Logger(label: "ios-mcp.command-executor")

    public init() {}

    /// Execute a command and return its output.
    ///
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/usr/bin/xcrun").
    ///   - arguments: Argument array passed directly to the process.
    ///   - timeout: Maximum execution time in seconds. Nil for no timeout.
    ///   - environment: Additional environment variables merged with the current process env.
    /// - Returns: The result containing stdout, stderr, and exit code.
    public func execute(
        executable: String,
        arguments: [String] = [],
        timeout: TimeInterval? = 60,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        // Pre-run cancellation check
        if Task.isCancelled {
            throw CancellationError()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let environment {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        logger.debug("Executing: \(executable) \(arguments.joined(separator: " "))")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let rawStdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let rawStderr = String(data: stderrData, encoding: .utf8) ?? ""

                    let result = CommandResult(
                        stdout: Redactor.redact(rawStdout),
                        stderr: Redactor.redact(rawStderr),
                        exitCode: process.terminationStatus
                    )

                    continuation.resume(returning: result)
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ToolError(
                        code: .commandFailed,
                        message: "Failed to launch \(executable): \(error.localizedDescription)"
                    ))
                    return
                }

                if let timeout {
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

// MARK: - CommandResult

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}
