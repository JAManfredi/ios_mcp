//
//  BuildRunSimToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("build_run_sim")
struct BuildRunSimToolTests {

    private let buildSettingsOutput = """
    Build settings for action build and target MyApp:
        PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp
        PRODUCT_NAME = MyApp
        BUILT_PRODUCTS_DIR = /tmp/Build/Products/Debug-iphonesimulator
        FULL_PRODUCT_NAME = MyApp.app
    """

    private let xcresultJSON = """
    { "actions": [] }
    """

    @Test("Builds, installs, and launches app")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let installCapture = ArgCapture()
        let launchCapture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if exec.contains("xcodebuild") && args.contains("-showBuildSettings") {
                return CommandResult(stdout: self.buildSettingsOutput, stderr: "", exitCode: 0)
            }
            if exec.contains("xcrun") && args.contains("install") {
                await installCapture.capture(args)
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if exec.contains("xcrun") && args.contains("launch") {
                await launchCapture.capture(args)
                return CommandResult(stdout: "com.example.MyApp: 99999", stderr: "", exitCode: 0)
            }
            // xcresulttool fallback
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "build_run_sim", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Build, install, and launch succeeded"))
            #expect(result.content.contains("Timing:"))
            #expect(result.content.contains("Bundle ID: com.example.MyApp"))
            #expect(result.content.contains("bundle_id = com.example.MyApp"))
        } else {
            Issue.record("Expected success response")
        }

        let installArgs = await installCapture.lastArgs
        #expect(installArgs.contains("install"))
        #expect(installArgs.contains("AAAA-1111"))
        #expect(installArgs.contains("/tmp/Build/Products/Debug-iphonesimulator/MyApp.app"))

        let launchArgs = await launchCapture.lastArgs
        #expect(launchArgs.contains("launch"))
        #expect(launchArgs.contains("com.example.MyApp"))

        let bundleID = await session.get(.bundleID)
        #expect(bundleID == "com.example.MyApp")
    }

    @Test("Build failure stops before install")
    func buildFailure() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "Build failed", exitCode: 65)
            }
            // xcresulttool
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "build_run_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
            #expect(error.message.contains("Build failed"))
            #expect(error.message.contains("Elapsed:"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Install failure stops before launch")
    func installFailure() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if exec.contains("xcodebuild") && args.contains("-showBuildSettings") {
                return CommandResult(stdout: self.buildSettingsOutput, stderr: "", exitCode: 0)
            }
            if args.contains("install") {
                return CommandResult(stdout: "", stderr: "Failed to install", exitCode: 1)
            }
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "build_run_sim", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
            #expect(error.message.contains("simctl install failed"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Sets session bundle_id from build settings")
    func autoSetBundleID() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if exec.contains("xcodebuild") && args.contains("-showBuildSettings") {
                return CommandResult(stdout: self.buildSettingsOutput, stderr: "", exitCode: 0)
            }
            if args.contains("install") || args.contains("launch") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        _ = try await registry.callTool(name: "build_run_sim", arguments: [:])

        let bundleID = await session.get(.bundleID)
        #expect(bundleID == "com.example.MyApp")
    }

    @Test("Uses explicit bundle_id when provided")
    func explicitBundleID() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let launchCapture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec.contains("xcodebuild") && args.contains("build") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if exec.contains("xcodebuild") && args.contains("-showBuildSettings") {
                return CommandResult(stdout: self.buildSettingsOutput, stderr: "", exitCode: 0)
            }
            if args.contains("launch") {
                await launchCapture.capture(args)
            }
            if args.contains("install") || args.contains("launch") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: self.xcresultJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        _ = try await registry.callTool(
            name: "build_run_sim",
            arguments: ["bundle_id": .string("com.custom.id")]
        )

        let launchArgs = await launchCapture.lastArgs
        #expect(launchArgs.contains("com.custom.id"))
    }
}
