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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "device_screenshot", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Device screenshot captured"))
            #expect(result.content.contains("DEVICE-UDID"))
        } else {
            Issue.record("Expected success response")
        }
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "device_screenshot", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
