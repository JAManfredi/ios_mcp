//
//  MockVideoRecording.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

actor MockVideoRecording: VideoRecording {
    private var sessions: [String: String] = [:]
    private var nextID = "mock-recording-1"
    private(set) var stopAllCalled = false

    func startRecording(udid: String) async throws -> String {
        let sessionID = nextID
        sessions[sessionID] = udid
        return sessionID
    }

    func stopRecording(sessionID: String) async throws -> VideoRecordingResult {
        guard sessions[sessionID] != nil else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown video recording session: \(sessionID)"
            )
        }
        sessions[sessionID] = nil
        return VideoRecordingResult(
            path: "/tmp/mock-recording-\(sessionID).mp4",
            fileSize: 1_234_567
        )
    }

    func hasActiveRecording(sessionID: String) async -> Bool {
        sessions[sessionID] != nil
    }

    func stopAll() async {
        stopAllCalled = true
        sessions.removeAll()
    }

    func setNextID(_ id: String) {
        nextID = id
    }
}
