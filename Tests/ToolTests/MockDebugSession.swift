//
//  MockDebugSession.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Test helper that provides canned DebugSessionManaging responses without running real LLDB.
actor MockDebugSession: DebugSessionManaging {
    var nextSessionID: String = "mock-session-1"
    var attachedSessions: [String: (pid: Int?, bundleID: String?)] = [:]
    var commandResponses: [String: String] = [:]
    var lastCommand: String?
    var shouldFailDetach: Bool = false
    private var lockKeys: [String: String] = [:]
    private(set) var teardownAllCalled: Bool = false

    init() {}

    init(
        nextSessionID: String = "mock-session-1",
        commandResponses: [String: String] = [:]
    ) {
        self.nextSessionID = nextSessionID
        self.commandResponses = commandResponses
    }

    func attach(
        pid: Int?,
        bundleID: String?,
        udid: String?
    ) async throws -> String {
        let id = nextSessionID
        attachedSessions[id] = (pid: pid, bundleID: bundleID)
        return id
    }

    func detach(sessionID: String) async throws {
        guard attachedSessions[sessionID] != nil else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown debug session: \(sessionID)"
            )
        }
        attachedSessions[sessionID] = nil
    }

    func sendCommand(
        sessionID: String,
        command: String,
        timeout: TimeInterval
    ) async throws -> String {
        guard attachedSessions[sessionID] != nil else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown debug session: \(sessionID)"
            )
        }
        lastCommand = command
        return commandResponses[command] ?? "OK"
    }

    func isActive(sessionID: String) async -> Bool {
        attachedSessions[sessionID] != nil
    }

    func setNextSessionID(_ id: String) {
        nextSessionID = id
    }

    func storeLockKey(sessionID: String, lockKey: String) {
        lockKeys[sessionID] = lockKey
    }

    func removeLockKey(sessionID: String) -> String? {
        lockKeys.removeValue(forKey: sessionID)
    }

    func teardownAll() async {
        attachedSessions.removeAll()
        lockKeys.removeAll()
        teardownAllCalled = true
    }
}
