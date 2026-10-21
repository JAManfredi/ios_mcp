//
//  DebugSessionManager.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Logging

// MARK: - Protocol

/// Protocol for LLDB debug session management, enabling mock injection in tests.
public protocol DebugSessionManaging: Sendable {
    func attach(
        pid: Int?,
        bundleID: String?,
        udid: String?
    ) async throws -> String

    func detach(sessionID: String) async throws

    func sendCommand(
        sessionID: String,
        command: String,
        timeout: TimeInterval
    ) async throws -> String

    func isActive(sessionID: String) async -> Bool

    func storeLockKey(sessionID: String, lockKey: String) async
    func removeLockKey(sessionID: String) async -> String?
    func teardownAll() async
}

// MARK: - Manager

/// Actor managing persistent LLDB subprocesses for interactive debugging.
public actor LLDBSessionManager: DebugSessionManaging {
    private var sessions: [String: LLDBSession] = [:]
    private var lockKeys: [String: String] = [:]
    private let logger = Logger(label: "ios-mcp.lldb-audit")

    public init() {}

    public func attach(
        pid: Int?,
        bundleID: String?,
        udid: String?
    ) async throws -> String {
        let sessionID = UUID().uuidString

        let session = LLDBSession(id: sessionID)
        try await session.launch()

        let attachCommand: String
        if let pid {
            attachCommand = "process attach --pid \(pid)"
        } else if let bundleID {
            attachCommand = "process attach --name \(bundleID)"
        } else {
            throw ToolError(
                code: .invalidInput,
                message: "Either pid or bundleID must be provided for attach"
            )
        }

        _ = try await session.sendCommand(attachCommand, timeout: 60)
        logger.info("Attached session \(sessionID): \(attachCommand)")

        sessions[sessionID] = session
        return sessionID
    }

    public func detach(sessionID: String) async throws {
        guard let session = sessions[sessionID] else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown debug session: \(sessionID)"
            )
        }

        _ = try? await session.sendCommand("detach", timeout: 10)
        _ = try? await session.sendCommand("quit", timeout: 5)
        await session.terminate()
        sessions[sessionID] = nil

        logger.info("Detached session \(sessionID)")
    }

    public func sendCommand(
        sessionID: String,
        command: String,
        timeout: TimeInterval
    ) async throws -> String {
        guard let session = sessions[sessionID] else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown debug session: \(sessionID)"
            )
        }

        logger.info("[\(sessionID)] \(command)")
        return try await session.sendCommand(command, timeout: timeout)
    }

    public func isActive(sessionID: String) async -> Bool {
        sessions[sessionID] != nil
    }

    public func storeLockKey(sessionID: String, lockKey: String) {
        lockKeys[sessionID] = lockKey
    }

    public func removeLockKey(sessionID: String) -> String? {
        lockKeys.removeValue(forKey: sessionID)
    }

    public func teardownAll() async {
        for (id, session) in sessions {
            _ = try? await session.sendCommand("detach", timeout: 5)
            _ = try? await session.sendCommand("quit", timeout: 3)
            await session.terminate()
            logger.info("Torn down session \(id)")
        }
        sessions.removeAll()
        lockKeys.removeAll()
    }
}

// MARK: - Output Buffer

/// Thread-safe output buffer using a lock instead of actor isolation.
/// This avoids deadlocking when the actor's synchronous `waitForCompletion`
/// spin loop needs to read output written by the pipe's readability handler.
final class LLDBOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String = ""

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    func consumeThroughMarker(_ marker: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let range = storage.range(of: marker + "\n") else { return nil }
        // The marker is echoed on its own line, preceded by LLDB's prompt.
        let prefix = storage[..<range.lowerBound]
        let result = prefix.lastIndex(of: "\n").map { String(prefix[...$0]) } ?? ""
        storage.removeSubrange(..<range.upperBound)
        return result
    }

    func drain() -> String {
        lock.lock()
        let result = storage
        storage = ""
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        storage = ""
        lock.unlock()
    }
}

// MARK: - Session

/// Owns a single LLDB Process with bidirectional stdin/stdout pipes.
actor LLDBSession {
    let id: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let outputBuffer = LLDBOutputBuffer()

    private static let prompt = "(lldb) "

    init(id: String) {
        self.id = id
    }

    func launch() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["lldb", "--no-use-colors"]

        let stdin = Pipe()
        let stdout = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        // One pipe preserves ordering between diagnostics and command completion.
        proc.standardError = stdout

        try proc.run()

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        // Read on Foundation's dispatch queue, not a Swift concurrency task. A
        // blocking read inside a task holds a cooperative-pool thread, and while
        // `waitForCompletion` spins on another one, a small pool (CI runners have
        // three cores) can leave the reader unscheduled until the command times out.
        let buffer = outputBuffer
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                buffer.append(text)
            }
        }
    }

    func sendCommand(_ command: String, timeout: TimeInterval) throws -> String {
        guard let stdinPipe, let process, process.isRunning else {
            throw ToolError(
                code: .internalError,
                message: "LLDB process is not running"
            )
        }

        outputBuffer.clear()

        // With piped stdin LLDB echoes the prompt BEFORE executing a command.
        // An echoed trailing comment proves that the preceding command finished.
        let marker = "# ios-mcp-command-end-\(UUID().uuidString)"
        let commandData = Data((command + "\n" + marker + "\n").utf8)
        stdinPipe.fileHandleForWriting.write(commandData)

        let output = try waitForCompletion(marker: marker, timeout: timeout)
        return Redactor.redact(output
            .replacingOccurrences(of: Self.prompt + command + "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func terminate() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    // MARK: - Private

    private func waitForCompletion(marker: String, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let result = outputBuffer.consumeThroughMarker(marker) {
                return result
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let partial = outputBuffer.drain()
        throw ToolError(
            code: .timeout,
            message: "LLDB command timed out after \(Int(timeout))s",
            details: partial.isEmpty ? nil : Redactor.redact(partial)
        )
    }
}
