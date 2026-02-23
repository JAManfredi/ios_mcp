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

    func executeStreaming(
        executable: String,
        arguments: [String],
        timeout: TimeInterval?,
        environment: [String: String]?,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> CommandResult
}

public extension CommandExecuting {
    func executeStreaming(
        executable: String,
        arguments: [String],
        timeout: TimeInterval?,
        environment: [String: String]?,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> CommandResult {
        try await execute(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
    }
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

                // Place the child in its own process group so we can kill the entire tree
                let pid = process.processIdentifier
                setpgid(pid, 0)

                if let timeout {
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            Self.terminateProcessTree(process)
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning { Self.terminateProcessTree(process) }
        }
    }
    /// Execute a command, streaming stdout lines to a callback as they arrive.
    /// Returns the full result (stdout, stderr, exit code) once the process finishes.
    public func executeStreaming(
        executable: String,
        arguments: [String] = [],
        timeout: TimeInterval? = 60,
        environment: [String: String]? = nil,
        onOutput: @escaping @Sendable (String) async -> Void
    ) async throws -> CommandResult {
        if Task.isCancelled { throw CancellationError() }

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

        logger.debug("Executing (streaming): \(executable) \(arguments.joined(separator: " "))")

        // Accumulate stdout for the final result while streaming lines to the callback
        let stdoutAccumulator = StdoutAccumulator()

        return try await withTaskCancellationHandler {
            // Start reading stdout in a detached task so lines stream in real time
            let readTask = Task.detached {
                let handle = stdoutPipe.fileHandleForReading
                var buffer = Data()
                let newline = UInt8(ascii: "\n")

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    await stdoutAccumulator.append(chunk)
                    buffer.append(chunk)

                    // Extract complete lines
                    while let newlineIndex = buffer.firstIndex(of: newline) {
                        let lineData = buffer[buffer.startIndex...newlineIndex]
                        buffer = Data(buffer[buffer.index(after: newlineIndex)...])
                        if let line = String(data: lineData, encoding: .utf8) {
                            await onOutput(line)
                        }
                    }
                }

                // Flush any remaining partial line
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    await onOutput(line)
                }
            }

            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    Task {
                        // Wait for the read task to drain all output
                        await readTask.value

                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let rawStdout = await stdoutAccumulator.data
                        let stdoutStr = String(data: rawStdout, encoding: .utf8) ?? ""
                        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                        let result = CommandResult(
                            stdout: Redactor.redact(stdoutStr),
                            stderr: Redactor.redact(stderrStr),
                            exitCode: process.terminationStatus
                        )

                        continuation.resume(returning: result)
                    }
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

                let pid = process.processIdentifier
                setpgid(pid, 0)

                if let timeout {
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            Self.terminateProcessTree(process)
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning { Self.terminateProcessTree(process) }
        }
    }

    /// Terminate a process and its entire process group.
    /// Sends SIGTERM to the group first, then SIGKILL after a grace period.
    private static func terminateProcessTree(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            kill(-pid, SIGKILL)
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

// MARK: - StdoutAccumulator

/// Actor that accumulates stdout data from streaming reads.
private actor StdoutAccumulator {
    private var _data = Data()

    var data: Data { _data }

    func append(_ chunk: Data) {
        _data.append(chunk)
    }
}
