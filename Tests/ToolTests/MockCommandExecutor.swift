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

// MARK: - Test Validator

/// JSON containing common test UDIDs for validator passthrough.
let validatorSimctlJSON = """
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
      { "udid": "AAAA-1111", "name": "iPhone 16", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "SESSION-UDID", "name": "iPhone 15", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "TEST-UDID", "name": "iPhone 14", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "RESOLVED-UUID", "name": "iPhone 16", "state": "Shutdown", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "VALID-UDID-1111", "name": "iPhone 16 Pro", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "SIM-1111", "name": "iPhone 16 Pro Max", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "SIM-2222", "name": "iPhone SE", "state": "Shutdown", "isAvailable": true, "deviceTypeIdentifier": "t" },
      { "udid": "UUID-123", "name": "iPad Pro", "state": "Booted", "isAvailable": true, "deviceTypeIdentifier": "t" }
    ]
  }
}
"""

/// Creates a DefaultsValidator backed by a mock executor that always returns valid simctl JSON.
func testValidator() -> DefaultsValidator {
    DefaultsValidator(
        executor: MockCommandExecutor.succeedingWith(validatorSimctlJSON),
        fileExists: { _ in true }
    )
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
