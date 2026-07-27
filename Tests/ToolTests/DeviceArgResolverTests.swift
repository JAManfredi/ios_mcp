//
//  DeviceArgResolverTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

/// End of the chain: whatever identifier a caller supplies, the string handed
/// to `xcodebuild -destination` must carry the hardware UDID.
@Suite("DeviceArgResolver")
struct DeviceArgResolverTests {

    private static let devicectlJSON = """
    {
      "result": {
        "devices": [
          {
            "identifier": "7026A743-5667-5BAD-8820-9757B8F762A0",
            "hardwareProperties": { "udid": "00008140-00065DA40862201C" },
            "deviceProperties": { "name": "JM iPhone" }
          }
        ]
      }
    }
    """

    private struct StubExecutor: CommandExecuting {
        func execute(
            executable: String,
            arguments: [String],
            timeout: TimeInterval?,
            environment: [String: String]?
        ) async throws -> CommandResult {
            CommandResult(stdout: DeviceArgResolverTests.devicectlJSON, stderr: "", exitCode: 0)
        }
    }

    private func resolve(_ udid: String) async -> Result<String, ToolError> {
        await resolveDeviceUDID(
            from: ["device_udid": .string(udid)],
            session: SessionStore(),
            validator: DefaultsValidator(executor: StubExecutor())
        )
    }

    @Test("A CoreDevice UUID produces a hardware-UDID destination")
    func coreDeviceUUIDBecomesHardwareDestination() async {
        let resolved = try? (await resolve("7026A743-5667-5BAD-8820-9757B8F762A0")).get()
        #expect(resolved != nil)
        #expect(
            deviceDestination(udid: resolved ?? "")
                == "platform=iOS,id=00008140-00065DA40862201C"
        )
    }

    @Test("A hardware UDID passes through unchanged")
    func hardwareUDIDUnchanged() async {
        let resolved = try? (await resolve("00008140-00065DA40862201C")).get()
        #expect(
            deviceDestination(udid: resolved ?? "")
                == "platform=iOS,id=00008140-00065DA40862201C"
        )
    }

    @Test("An unknown identifier is rejected before reaching xcodebuild")
    func unknownRejected() async {
        let result = await resolve("no-such-device")
        guard case .failure(let error) = result else {
            Issue.record("expected rejection")
            return
        }
        #expect(error.code == .staleDefault)
    }
}
