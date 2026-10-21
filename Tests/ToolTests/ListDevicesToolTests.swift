//
//  ListDevicesToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

private let devicectlJSON = """
{"result":{"devices":[{"identifier":"00001111-AAAA-BBBB-CCCC","deviceProperties":{"name":"Jared's iPhone","osVersionNumber":"18.0"},"hardwareProperties":{"marketingName":"iPhone 16 Pro"},"connectionProperties":{"transportType":"usb"}}]}}
"""

private let twoDevicesJSON = """
{"result":{"devices":[{"identifier":"DEVICE-1","deviceProperties":{"name":"iPhone A","osVersionNumber":"18.0"},"hardwareProperties":{"marketingName":"iPhone 16"},"connectionProperties":{"transportType":"usb"}},{"identifier":"DEVICE-2","deviceProperties":{"name":"iPhone B","osVersionNumber":"17.0"},"hardwareProperties":{"marketingName":"iPhone 15"},"connectionProperties":{"transportType":"wifi"}}]}}
"""

// Reduced, sanitized Xcode 27.1 output with deprecated fields omitted.
private let v5JSON = """
{"info":{"jsonVersion":5},"result":{"devices":[
  {"identifier":"CORE-1","properties":{
    "hardware":{"udid":"00008140-HW","marketingName":"iPhone 17 Pro","reality":"physical"},
    "state":{"name":"Jared's iPhone","bootState":"booted"},
    "software":{"osVersionNumber":{"components":[27,1],"originalComponentsCount":2,"stringValue":"27.1"}},
    "connection":{"transportType":"localNetwork"}
  }},
  {"identifier":"SIM-1","properties":{
    "hardware":{"udid":"SIM-UDID","reality":"simulated"},
    "state":{"name":"iPhone 17"}
  }}
]}}
"""

@Suite("list_devices")
struct ListDevicesToolTests {

    @Test("Parses devicectl JSON v5 and ignores simulators")
    func v5Schema() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("devicectl") { return CommandResult(stdout: v5JSON, stderr: "", exitCode: 0) }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "list_devices", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Connected devices (1)"))
            #expect(result.content.contains("Jared's iPhone"))
            #expect(result.content.contains("iPhone 17 Pro, iOS 27.1, localNetwork"))
            #expect(!result.content.contains("SIM-UDID"))
        } else {
            Issue.record("Expected success response")
        }

        #expect(await session.get(.deviceUDID) == "00008140-HW")
    }

    @Test("Lists connected devices and auto-sets session default for single device")
    func singleDevice() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if args.contains("devicectl") && args.contains("list") {
                return CommandResult(stdout: devicectlJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "list_devices", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Connected devices (1)"))
            #expect(result.content.contains("Jared's iPhone"))
            #expect(result.content.contains("iPhone 16 Pro"))
            #expect(result.content.contains("device_udid = 00001111-AAAA-BBBB-CCCC"))
        } else {
            Issue.record("Expected success response")
        }

        let udid = await session.get(.deviceUDID)
        #expect(udid == "00001111-AAAA-BBBB-CCCC")
    }

    @Test("Does not auto-set session default for multiple devices")
    func multipleDevices() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if args.contains("devicectl") { return CommandResult(stdout: twoDevicesJSON, stderr: "", exitCode: 0) }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "list_devices", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Connected devices (2)"))
            #expect(!result.content.contains("device_udid ="))
        } else {
            Issue.record("Expected success response")
        }

        let udid = await session.get(.deviceUDID)
        #expect(udid == nil)
    }

    @Test("Handles devicectl failure")
    func devicectlFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if args.contains("devicectl") { return CommandResult(stdout: "", stderr: "devicectl not found", exitCode: 1) }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "list_devices", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
