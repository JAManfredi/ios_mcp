//
//  MockCommandExecutor.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Test helper that returns canned CommandResult values without running real processes.
struct MockCommandExecutor: CommandExecuting {
    let handler: @Sendable (String, [String]) async throws -> CommandResult

    init(handler: @escaping @Sendable (String, [String]) async throws -> CommandResult) {
        self.handler = handler
    }

    func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval?,
        environment: [String: String]?
    ) async throws -> CommandResult {
        try await handler(executable, arguments)
    }
}

extension MockCommandExecutor {
    /// Creates a mock that always returns the given stdout with exit code 0.
    static func succeedingWith(_ stdout: String) -> MockCommandExecutor {
        MockCommandExecutor { _, _ in
            CommandResult(stdout: stdout, stderr: "", exitCode: 0)
        }
    }

    /// Creates a mock that always fails with the given stderr and exit code.
    static func failingWith(
        stderr: String,
        exitCode: Int32 = 1
    ) -> MockCommandExecutor {
        MockCommandExecutor { _, _ in
            CommandResult(stdout: "", stderr: stderr, exitCode: exitCode)
        }
    }
}

/// Actor-based container for capturing arguments in tests (Sendable-safe).
actor ArgCapture {
    private(set) var lastArgs: [String] = []

    func capture(_ args: [String]) {
        lastArgs = args
    }
}

/// Test helper that provides canned LogCapturing responses without real processes.
actor MockLogCapture: LogCapturing {
    private var sessions: [String: LogCaptureResult] = [:]
    private var nextID = "mock-session-1"

    init() {}

    init(
        nextID: String = "mock-session-1",
        cannedResult: LogCaptureResult? = nil
    ) {
        self.nextID = nextID
        if let cannedResult {
            sessions[nextID] = cannedResult
        }
    }

    func startCapture(
        udid: String,
        predicate: String?,
        bufferSize: Int
    ) async throws -> String {
        let id = nextID
        if sessions[id] == nil {
            sessions[id] = LogCaptureResult(entries: [], droppedEntryCount: 0, totalEntriesReceived: 0)
        }
        return id
    }

    func stopCapture(sessionID: String) async throws -> LogCaptureResult {
        guard let result = sessions[sessionID] else {
            throw ToolError(
                code: .invalidInput,
                message: "Unknown log capture session: \(sessionID)"
            )
        }
        sessions[sessionID] = nil
        return result
    }

    func hasActiveCapture(sessionID: String) async -> Bool {
        sessions[sessionID] != nil
    }
}
