//
//  DeviceCanonicalizationTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

/// Both identifiers must reach `xcodebuild` as the hardware UDID.
///
/// Accepting either identifier at validation while passing the caller's value
/// straight through means a CoreDevice UUID clears the check and then fails
/// inside xcodebuild with "Unable to find a device" — a message that points at
/// the hardware rather than at the identifier.
@Suite("Device canonicalization")
struct DeviceCanonicalizationTests {

    private static let devicectlJSON = """
    {
      "result": {
        "devices": [
          {
            "identifier": "7026A743-5667-5BAD-8820-9757B8F762A0",
            "hardwareProperties": {
              "udid": "00008140-00065DA40862201C",
              "marketingName": "iPhone 16 Pro"
            },
            "deviceProperties": { "name": "JM iPhone" }
          }
        ]
      }
    }
    """

    private static let hardwareUDID = "00008140-00065DA40862201C"
    private static let coreDeviceUUID = "7026A743-5667-5BAD-8820-9757B8F762A0"

    private struct StubExecutor: CommandExecuting {
        let handler: @Sendable () async throws -> CommandResult

        func execute(
            executable: String,
            arguments: [String],
            timeout: TimeInterval?,
            environment: [String: String]?
        ) async throws -> CommandResult {
            try await handler()
        }
    }

    private func validator(stdout: String = devicectlJSON) -> DefaultsValidator {
        DefaultsValidator(executor: StubExecutor {
            CommandResult(stdout: stdout, stderr: "", exitCode: 0)
        })
    }

    @Test("A CoreDevice UUID canonicalizes to the hardware UDID")
    func canonicalizesCoreDeviceUUID() async {
        let result = await validator().canonicalDeviceUDID(Self.coreDeviceUUID)
        #expect((try? result.get()) == Self.hardwareUDID)
    }

    @Test("A hardware UDID canonicalizes to itself")
    func canonicalizesHardwareUDID() async {
        let result = await validator().canonicalDeviceUDID(Self.hardwareUDID)
        #expect((try? result.get()) == Self.hardwareUDID)
    }

    @Test("An unknown identifier is rejected and lists real candidates")
    func rejectsUnknown() async {
        let result = await validator().canonicalDeviceUDID("not-a-device")
        guard case .failure(let error) = result else {
            Issue.record("expected rejection")
            return
        }
        #expect(error.code == .staleDefault)
        #expect(error.details?.contains(Self.hardwareUDID) == true)
    }

    @Test("An unavailable devicectl degrades to the caller's value")
    func degradesGracefully() async {
        let failing = DefaultsValidator(executor: StubExecutor {
            throw ToolError(code: .commandFailed, message: "devicectl unavailable")
        })
        let result = await failing.canonicalDeviceUDID(Self.coreDeviceUUID)
        #expect((try? result.get()) == Self.coreDeviceUUID)
    }

    @Test("A record with neither identifier yields no destination UDID")
    func rejectsUnidentifiedRecord() {
        let malformed: [String: Any] = ["deviceProperties": ["name": "Mystery"]]
        #expect(DeviceIdentity.destinationUDID(for: malformed) == nil)
    }
}
