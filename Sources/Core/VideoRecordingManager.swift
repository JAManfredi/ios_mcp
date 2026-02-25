//
//  VideoRecordingManager.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Logging

// MARK: - Protocol

/// Protocol for video recording, enabling mock injection in tests.
public protocol VideoRecording: Sendable {
    func startRecording(udid: String) async throws -> String
    func stopRecording(sessionID: String) async throws -> VideoRecordingResult
    func hasActiveRecording(sessionID: String) async -> Bool
    func stopAll() async
}

// MARK: - Types

public struct VideoRecordingResult: Sendable {
    public let path: String
    public let fileSize: Int

    public init(
        path: String,
        fileSize: Int
    ) {
        self.path = path
        self.fileSize = fileSize
    }
}

// MARK: - Manager

/// Actor managing background `simctl io recordVideo` processes.
public actor VideoRecordingManager: VideoRecording {
    private var sessions: [String: VideoRecordingSession] = [:]
    private let logger = Logger(label: "ios-mcp.video-recording")

    public init() {}

    public func startRecording(udid: String) async throws -> String {
        let sessionID = UUID().uuidString
        let outputPath = NSTemporaryDirectory() + "ios-mcp-recording-\(sessionID).mp4"

        let session = VideoRecordingSession(
            id: sessionID,
            udid: udid,
            outputPath: outputPath
        )

        try await session.start()
        sessions[sessionID] = session

        logger.debug("Started video recording \(sessionID) for simulator \(udid)")
        return sessionID
    }

    public func stopRecording(sessionID: String) async throws -> VideoRecordingResult {
        guard let session = sessions[sessionID] else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown video recording session: \(sessionID)"
            )
        }

        let result = await session.stop()
        sessions[sessionID] = nil

        logger.debug("Stopped video recording \(sessionID): \(result.fileSize) bytes")
        return result
    }

    public func hasActiveRecording(sessionID: String) async -> Bool {
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

/// Owns a single `simctl io recordVideo` Process.
actor VideoRecordingSession {
    let id: String
    let udid: String
    let outputPath: String
    private var process: Process?

    init(
        id: String,
        udid: String,
        outputPath: String
    ) {
        self.id = id
        self.udid = udid
        self.outputPath = outputPath
    }

    func start() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", outputPath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        try proc.run()
        self.process = proc
    }

    /// Stop recording. Uses SIGINT (not SIGTERM) so `simctl` finalizes the MP4 container.
    /// SIGTERM produces a corrupt file because the container header isn't written.
    func stop() -> VideoRecordingResult {
        if let proc = process, proc.isRunning {
            // SIGINT triggers graceful MP4 finalization
            proc.interrupt()

            // Wait up to 5 seconds for the process to finish writing the MP4
            let deadline = Date().addingTimeInterval(5)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            // Force terminate if still running
            if proc.isRunning {
                proc.terminate()
            }
        }
        process = nil

        let fileSize: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let size = attrs[.size] as? Int {
            fileSize = size
        } else {
            fileSize = 0
        }

        return VideoRecordingResult(
            path: outputPath,
            fileSize: fileSize
        )
    }
}
