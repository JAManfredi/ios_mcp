//
//  DeviceScreenshotToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("device_screenshot")
struct DeviceScreenshotToolTests {

    @Test("Captures screenshot from device")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.deviceUDID, value: "DEVICE-UDID")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("devicectl") && args.contains("screenshot") {
                #expect(Array(args.prefix(4)) == ["devicectl", "device", "capture", "screenshot"])
                if let i = args.firstIndex(of: "--destination"), i + 1 < args.count {
                    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: args[i + 1]))
                }
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if args.contains("devicectl") && args.contains("list") {
                return CommandResult(stdout: """
                {"result":{"devices":[{"identifier":"DEVICE-UDID","deviceProperties":{"name":"Test iPhone"}}]}}
                """, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        let deviceValidator = DefaultsValidator(executor: executor, fileExists: { _ in true })

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "device_screenshot", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Device screenshot captured"))
            #expect(result.content.contains("DEVICE-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when devicectl succeeds but writes no file")
    func emptyOutput() async throws {
        let session = SessionStore()
        await session.set(.deviceUDID, value: "DEVICE-UDID")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("devicectl") && args.contains("list") {
                return CommandResult(stdout: """
                {"result":{"devices":[{"identifier":"DEVICE-UDID","deviceProperties":{"name":"Test iPhone"}}]}}
                """, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let deviceValidator = DefaultsValidator(executor: executor, fileExists: { _ in true })

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "device_screenshot", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Builds devicectl capture arguments")
    func captureArgs() {
        #expect(deviceCaptureScreenshotArgs(udid: "U", destination: "/tmp/x.png") ==
            ["devicectl", "device", "capture", "screenshot", "--device", "U", "--destination", "/tmp/x.png"])
    }

    @Test("Errors when no device UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("devicectl") && args.contains("list") {
                return CommandResult(stdout: """
                {"result":{"devices":[]}}
                """, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        let deviceValidator = DefaultsValidator(executor: executor, fileExists: { _ in true })

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "device_screenshot", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
