//
//  DefaultsValidatorTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("DefaultsValidator")
struct DefaultsValidatorTests {

    private static let simctlJSON = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
          {
            "udid": "VALID-UDID-1111",
            "name": "iPhone 16",
            "state": "Booted",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
          }
        ]
      }
    }
    """

    @Test("Valid UDID passes validation")
    func validUDIDPasses() async {
        let executor = MockValidator.executor(stdout: Self.simctlJSON)
        let validator = DefaultsValidator(executor: executor)
        let error = await validator.validateSimulatorUDID("VALID-UDID-1111")
        #expect(error == nil)
    }

    @Test("Stale UDID fails validation with candidates")
    func staleUDIDFails() async {
        let executor = MockValidator.executor(stdout: Self.simctlJSON)
        let validator = DefaultsValidator(executor: executor)
        let error = await validator.validateSimulatorUDID("NONEXISTENT-UDID")
        #expect(error != nil)
        #expect(error?.code == .staleDefault)
        #expect(error?.details?.contains("VALID-UDID-1111") == true)
        #expect(error?.details?.contains("iPhone 16") == true)
    }

    @Test("Stale UDID with no available devices has nil details")
    func staleUDIDNoAvailableDevices() async {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "ONLY-UDID", "name": "iPhone 16", "state": "Shutdown", "isAvailable": false }
            ]
          }
        }
        """
        let executor = MockValidator.executor(stdout: json)
        let validator = DefaultsValidator(executor: executor)
        let error = await validator.validateSimulatorUDID("NONEXISTENT-UDID")
        #expect(error != nil)
        #expect(error?.code == .staleDefault)
        #expect(error?.details == nil)
    }

    @Test("Valid path passes validation")
    func validPathPasses() {
        let validator = DefaultsValidator(executor: MockValidator.executor(stdout: ""))
        let error = validator.validatePathExists(NSTemporaryDirectory(), label: "Workspace")
        #expect(error == nil)
    }

    @Test("Stale path fails validation")
    func stalePathFails() {
        let validator = DefaultsValidator(executor: MockValidator.executor(stdout: ""))
        let error = validator.validatePathExists("/nonexistent/path/to/nowhere.xcworkspace", label: "Workspace")
        #expect(error != nil)
        #expect(error?.code == .staleDefault)
    }

    @Test("simctl failure does not block tools")
    func simctlFailureDoesNotBlock() async {
        let executor = MockValidator.throwingExecutor()
        let validator = DefaultsValidator(executor: executor)
        let error = await validator.validateSimulatorUDID("ANY-UDID")
        #expect(error == nil)
    }
}

// MARK: - Test Helpers

private enum MockValidator {
    struct Executor: CommandExecuting {
        let handler: @Sendable (String, [String]) async throws -> CommandResult

        func execute(
            executable: String,
            arguments: [String],
            timeout: TimeInterval?,
            environment: [String: String]?
        ) async throws -> CommandResult {
            try await handler(executable, arguments)
        }
    }

    static func executor(stdout: String) -> Executor {
        Executor { _, _ in
            CommandResult(stdout: stdout, stderr: "", exitCode: 0)
        }
    }

    static func throwingExecutor() -> Executor {
        Executor { _, _ in
            throw ToolError(code: .commandFailed, message: "simctl unavailable")
        }
    }
}
