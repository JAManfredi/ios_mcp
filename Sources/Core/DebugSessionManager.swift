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
/// This avoids deadlocking when the actor's synchronous `waitForPrompt`
/// spin loop needs to read output written by a detached read task.
final class LLDBOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String = ""

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    func consumeIfPrompt(_ prompt: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard storage.contains(prompt) else { return nil }
        let result = storage
            .replacingOccurrences(of: prompt, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        storage = ""
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
    private var readTask: Task<Void, Never>?

    private static let prompt = "(lldb) "

    init(id: String) {
        self.id = id
    }

    func launch() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["lldb"]

        let stdin = Pipe()
        let stdout = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = Pipe() // discard stderr

        try proc.run()

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        let fileHandle = stdout.fileHandleForReading
        let buffer = outputBuffer
        readTask = Task.detached {
            while !Task.isCancelled {
                let data = fileHandle.availableData
                guard !data.isEmpty else { break }
                if let text = String(data: data, encoding: .utf8) {
                    buffer.append(text)
                }
            }
        }

        // Wait for initial prompt
        _ = try? waitForPrompt(timeout: 10)
    }

    func sendCommand(_ command: String, timeout: TimeInterval) throws -> String {
        guard let stdinPipe, let process, process.isRunning else {
            throw ToolError(
                code: .internalError,
                message: "LLDB process is not running"
            )
        }

        outputBuffer.clear()

        let commandData = Data((command + "\n").utf8)
        stdinPipe.fileHandleForWriting.write(commandData)

        return try waitForPrompt(timeout: timeout)
    }

    func terminate() {
        readTask?.cancel()
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        readTask = nil
    }

    // MARK: - Private

    private func waitForPrompt(timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let result = outputBuffer.consumeIfPrompt(Self.prompt) {
                return result
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let partial = outputBuffer.drain()
        throw ToolError(
            code: .timeout,
            message: "LLDB command timed out after \(Int(timeout))s",
            details: partial.isEmpty ? nil : partial
        )
    }
}
