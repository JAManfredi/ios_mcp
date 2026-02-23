//
//  LogCaptureManager.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Logging

// MARK: - Protocol

/// Protocol for log capture, enabling mock injection in tests.
public protocol LogCapturing: Sendable {
    func startCapture(
        udid: String,
        predicate: String?,
        bufferSize: Int
    ) async throws -> String

    func stopCapture(sessionID: String) async throws -> LogCaptureResult

    func hasActiveCapture(sessionID: String) async -> Bool

    func stopAll() async
}

// MARK: - Types

public struct LogEntry: Sendable {
    public let timestamp: String
    public let processName: String
    public let pid: Int
    public let subsystem: String
    public let category: String
    public let level: String
    public let message: String

    public init(
        timestamp: String,
        processName: String,
        pid: Int,
        subsystem: String,
        category: String,
        level: String,
        message: String
    ) {
        self.timestamp = timestamp
        self.processName = processName
        self.pid = pid
        self.subsystem = subsystem
        self.category = category
        self.level = level
        self.message = message
    }
}

public struct LogCaptureResult: Sendable {
    public let entries: [LogEntry]
    public let droppedEntryCount: Int
    public let totalEntriesReceived: Int

    public init(
        entries: [LogEntry],
        droppedEntryCount: Int,
        totalEntriesReceived: Int
    ) {
        self.entries = entries
        self.droppedEntryCount = droppedEntryCount
        self.totalEntriesReceived = totalEntriesReceived
    }
}

// MARK: - Manager

/// Actor managing background `simctl spawn <udid> log stream` processes.
public actor LogCaptureManager: LogCapturing {
    private var sessions: [String: LogCaptureSession] = [:]
    private let logger = Logger(label: "ios-mcp.log-capture")

    public init() {}

    public func startCapture(
        udid: String,
        predicate: String?,
        bufferSize: Int
    ) async throws -> String {
        let sessionID = UUID().uuidString

        var simctlArgs = ["simctl", "spawn", udid, "log", "stream", "--style", "json"]
        if let predicate {
            simctlArgs += ["--predicate", predicate]
        }

        let session = LogCaptureSession(
            id: sessionID,
            udid: udid,
            bufferSize: bufferSize,
            simctlArgs: simctlArgs
        )

        try await session.start()
        sessions[sessionID] = session

        logger.debug("Started log capture \(sessionID) for simulator \(udid)")
        return sessionID
    }

    public func stopCapture(sessionID: String) async throws -> LogCaptureResult {
        guard let session = sessions[sessionID] else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown log capture session: \(sessionID)"
            )
        }

        let result = await session.stop()
        sessions[sessionID] = nil

        logger.debug("Stopped log capture \(sessionID): \(result.entries.count) entries")
        return result
    }

    public func hasActiveCapture(sessionID: String) async -> Bool {
        sessions[sessionID] != nil
    }

    public func stopAll() async {
        for (_, session) in sessions {
            _ = await session.stop()
        }
        sessions.removeAll()
    }
}

// MARK: - Session

/// Owns a single `log stream` Process and its ring buffer.
actor LogCaptureSession {
    let id: String
    let udid: String
    private var buffer: RingBuffer<LogEntry>
    private var totalReceived: Int = 0
    private var process: Process?
    private var readTask: Task<Void, Never>?
    private let simctlArgs: [String]

    /// 10 MB payload limit per §4.4 of the tech doc.
    static let maxPayloadBytes = 10_485_760

    init(
        id: String,
        udid: String,
        bufferSize: Int,
        simctlArgs: [String]
    ) {
        self.id = id
        self.udid = udid
        self.buffer = RingBuffer(
            capacity: bufferSize,
            maxBytes: Self.maxPayloadBytes,
            sizeEstimator: { entry in
                entry.timestamp.utf8.count
                    + entry.processName.utf8.count
                    + entry.subsystem.utf8.count
                    + entry.category.utf8.count
                    + entry.level.utf8.count
                    + entry.message.utf8.count
                    + 64 // JSON overhead (keys, quotes, braces)
            }
        )
        self.simctlArgs = simctlArgs
    }

    func start() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = simctlArgs

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe() // discard stderr

        try proc.run()
        self.process = proc

        let fileHandle = pipe.fileHandleForReading
        readTask = Task.detached { [weak self] in
            let lineBuffer = LineBuffer(fileHandle: fileHandle)
            for await line in lineBuffer {
                guard let self else { break }
                if let entry = parseLogLine(line) {
                    await self.appendEntry(entry)
                }
            }
        }
    }

    func stop() -> LogCaptureResult {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        readTask?.cancel()
        process = nil
        readTask = nil

        return LogCaptureResult(
            entries: buffer.toArray(),
            droppedEntryCount: buffer.droppedCount,
            totalEntriesReceived: totalReceived
        )
    }

    fileprivate func appendEntry(_ entry: LogEntry) {
        totalReceived += 1
        buffer.append(entry)
    }
}

// MARK: - Log Line Parser

/// Parses a single JSON line from `log stream --style json`.
func parseLogLine(_ line: String) -> LogEntry? {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return LogEntry(
        timestamp: json["timestamp"] as? String ?? "",
        processName: json["processImagePath"] as? String
            ?? json["processName"] as? String
            ?? json["process"] as? String
            ?? "",
        pid: json["processID"] as? Int ?? json["pid"] as? Int ?? 0,
        subsystem: json["subsystem"] as? String ?? "",
        category: json["category"] as? String ?? "",
        level: json["messageType"] as? String ?? json["level"] as? String ?? "",
        message: json["eventMessage"] as? String ?? json["message"] as? String ?? ""
    )
}

// MARK: - Line Buffer

/// Async sequence that reads lines from a file handle.
struct LineBuffer: AsyncSequence {
    typealias Element = String
    let fileHandle: FileHandle

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(fileHandle: fileHandle)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let fileHandle: FileHandle
        var remainder = ""

        mutating func next() async -> String? {
            while !Task.isCancelled {
                if let newlineIndex = remainder.firstIndex(of: "\n") {
                    let line = String(remainder[remainder.startIndex..<newlineIndex])
                    remainder = String(remainder[remainder.index(after: newlineIndex)...])
                    if !line.isEmpty { return line }
                }

                let data = fileHandle.availableData
                guard !data.isEmpty else { return nil }
                remainder += String(data: data, encoding: .utf8) ?? ""
            }
            return nil
        }
    }
}
