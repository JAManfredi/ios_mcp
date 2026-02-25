//
//  BuildDeviceToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("build_device")
struct BuildDeviceToolTests {

    @Test("Builds for device with session defaults")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.deviceUDID, value: "DEVICE-UDID")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/xcodebuild" {
                await capture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            // Validator mock: devicectl returns JSON with the device
            if args.contains("devicectl") && args.contains("list") {
                return CommandResult(stdout: """
                {"result":{"devices":[{"identifier":"DEVICE-UDID","deviceProperties":{"name":"Test iPhone"}}]}}
                """, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        let deviceValidator = DefaultsValidator(executor: executor, fileExists: { _ in true })

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "build_device", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Device build succeeded"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("-workspace"))
        #expect(args.contains("-destination"))
        #expect(args.contains("platform=iOS,id=DEVICE-UDID"))
        #expect(args.contains("build"))
    }

    @Test("Errors when no scheme specified")
    func missingScheme() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.deviceUDID, value: "DEVICE-UDID")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("devicectl") {
                return CommandResult(stdout: """
                {"result":{"devices":[{"identifier":"DEVICE-UDID"}]}}
                """, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        let deviceValidator = DefaultsValidator(executor: executor, fileExists: { _ in true })

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: deviceValidator, videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "build_device", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("scheme"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
