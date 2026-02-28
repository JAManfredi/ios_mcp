//
//  ShowBuildSettingsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("show_build_settings")
struct ShowBuildSettingsToolTests {

    // MARK: - Parser Tests

    private let sampleOutput = """
    Build settings for action build and target MyApp:
        PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp
        PRODUCT_NAME = MyApp
        SDKROOT = iphoneos
        SWIFT_VERSION = 5.0
        CONFIGURATION = Debug
        IPHONEOS_DEPLOYMENT_TARGET = 17.0
        CODE_SIGN_IDENTITY = Apple Development
        CODE_SIGN_STYLE = Automatic
        DEVELOPMENT_TEAM = ABC123
        SOME_RANDOM_SETTING = should_be_filtered
        ANOTHER_SETTING = also_filtered
    """

    @Test("Parses KEY = VALUE lines correctly")
    func parseBuildSettingsOutput() {
        let settings = parseBuildSettings(sampleOutput)

        #expect(settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.MyApp")
        #expect(settings["PRODUCT_NAME"] == "MyApp")
        #expect(settings["SDKROOT"] == "iphoneos")
        #expect(settings["SWIFT_VERSION"] == "5.0")
        #expect(settings["CONFIGURATION"] == "Debug")
        #expect(settings["SOME_RANDOM_SETTING"] == "should_be_filtered")
    }

    @Test("Handles empty output")
    func parseEmptyOutput() {
        let settings = parseBuildSettings("")
        #expect(settings.isEmpty)
    }

    @Test("Handles lines without equals sign")
    func parseNoEquals() {
        let output = """
        Build settings for action build and target MyApp:
            NOT_A_SETTING
            VALID_KEY = valid_value
        """
        let settings = parseBuildSettings(output)
        #expect(settings.count == 1)
        #expect(settings["VALID_KEY"] == "valid_value")
    }

    @Test("Splits on first delimiter only when value contains equals")
    func parseValueContainingEquals() {
        let output = """
            OTHER_LDFLAGS = -framework UIKit -Xlinker -rpath=/usr/lib
        """
        let settings = parseBuildSettings(output)
        #expect(settings["OTHER_LDFLAGS"] == "-framework UIKit -Xlinker -rpath=/usr/lib")
    }

    @Test("Parses paths with spaces in values")
    func parsePathsWithSpaces() {
        let output = """
            BUILD_DIR = /Users/dev/Library/Developer/Xcode/DerivedData/My App-abc123/Build/Products
        """
        let settings = parseBuildSettings(output)
        #expect(settings["BUILD_DIR"] == "/Users/dev/Library/Developer/Xcode/DerivedData/My App-abc123/Build/Products")
    }

    @Test("Skips lines where value is empty")
    func parseEmptyValues() {
        let output = """
            SOME_KEY =
            OTHER_KEY = value
        """
        let settings = parseBuildSettings(output)
        // Empty values lack the " = " delimiter after trimming, so they're skipped
        #expect(settings["SOME_KEY"] == nil)
        #expect(settings["OTHER_KEY"] == "value")
    }

    // MARK: - Tool Integration

    @Test("Returns curated settings")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(sampleOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "show_build_settings", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp"))
            #expect(result.content.contains("SDKROOT = iphoneos"))
            // Non-curated keys should be filtered out
            #expect(!result.content.contains("SOME_RANDOM_SETTING"))
            #expect(!result.content.contains("ANOTHER_SETTING"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session defaults")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/some/path.xcworkspace")
        await session.set(.scheme, value: "MyScheme")
        await session.set(.configuration, value: "Release")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: sampleOutput, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        _ = try await registry.callTool(name: "show_build_settings", arguments: [:])

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-workspace"))
        #expect(capturedArgs.contains("/some/path.xcworkspace"))
        #expect(capturedArgs.contains("-scheme"))
        #expect(capturedArgs.contains("MyScheme"))
        #expect(capturedArgs.contains("-configuration"))
        #expect(capturedArgs.contains("Release"))
    }

    @Test("Errors when no scheme available")
    func missingScheme() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "show_build_settings", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No scheme"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no workspace or project available")
    func missingWorkspaceAndProject() async throws {
        let session = SessionStore()

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "show_build_settings",
            arguments: ["scheme": .string("MyScheme")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No workspace or project"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when xcodebuild fails")
    func commandFailure() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "xcodebuild: error: something went wrong")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "show_build_settings", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Auto-sets bundle ID from PRODUCT_BUNDLE_IDENTIFIER")
    func bundleIDAutoSet() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(sampleOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "show_build_settings", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: bundle_id = com.example.MyApp"))
        } else {
            Issue.record("Expected success response")
        }

        let bundleID = await session.get(.bundleID)
        #expect(bundleID == "com.example.MyApp")
    }

    @Test("Auto-sets configuration when explicitly provided")
    func configurationAutoSet() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(sampleOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "show_build_settings",
            arguments: ["configuration": .string("Release")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: configuration = Release"))
        } else {
            Issue.record("Expected success response")
        }

        let config = await session.get(.configuration)
        #expect(config == "Release")
    }

    @Test("Auto-sets deployment target from IPHONEOS_DEPLOYMENT_TARGET")
    func deploymentTargetAutoSet() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(sampleOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        _ = try await registry.callTool(name: "show_build_settings", arguments: [:])

        let target = await session.get(.deploymentTarget)
        #expect(target == "17.0")
    }

    @Test("Does not auto-set configuration from session fallback")
    func noConfigAutoSetFromSession() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")
        await session.set(.scheme, value: "MyApp")
        await session.set(.configuration, value: "Debug")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(sampleOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "show_build_settings", arguments: [:])

        if case .success(let result) = response {
            // Should not say "Session default set: configuration" since it fell back from session
            #expect(!result.content.contains("Session default set: configuration"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
