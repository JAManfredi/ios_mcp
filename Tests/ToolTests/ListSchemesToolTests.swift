//
//  ListSchemesToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("list_schemes")
struct ListSchemesToolTests {

    // MARK: - Parser Tests

    private let workspaceOutput = """
    Information about workspace "MyApp":
        Schemes:
            MyApp
            MyAppTests
            MyAppUITests
    """

    private let projectOutput = """
    Information about project "MyApp":
        Targets:
            MyApp
            MyAppTests

        Build Configurations:
            Debug
            Release

        If no build configuration is specified and -scheme is not passed then "Debug" is used.

        Schemes:
            MyApp
    """

    @Test("Parses workspace format with multiple schemes")
    func parseWorkspaceFormat() {
        let result = parseXcodebuildList(workspaceOutput)

        #expect(result.schemes == ["MyApp", "MyAppTests", "MyAppUITests"])
        #expect(result.targets.isEmpty)
        #expect(result.configurations.isEmpty)
    }

    @Test("Parses project format with targets, configs, and scheme")
    func parseProjectFormat() {
        let result = parseXcodebuildList(projectOutput)

        #expect(result.schemes == ["MyApp"])
        #expect(result.targets == ["MyApp", "MyAppTests"])
        #expect(result.configurations == ["Debug", "Release"])
    }

    @Test("Handles empty output")
    func parseEmptyOutput() {
        let result = parseXcodebuildList("")

        #expect(result.schemes.isEmpty)
        #expect(result.targets.isEmpty)
        #expect(result.configurations.isEmpty)
    }

    // MARK: - Tool Integration

    @Test("Returns schemes from xcodebuild output")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(workspaceOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "list_schemes", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("MyApp"))
            #expect(result.content.contains("MyAppTests"))
            #expect(result.content.contains("MyAppUITests"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session workspace")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/some/path.xcworkspace")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: workspaceOutput, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        _ = try await registry.callTool(name: "list_schemes", arguments: [:])

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-workspace"))
        #expect(capturedArgs.contains("/some/path.xcworkspace"))
    }

    @Test("Falls back to session project when no workspace")
    func sessionFallbackProject() async throws {
        let session = SessionStore()
        await session.set(.project, value: "/some/path.xcodeproj")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: projectOutput, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        _ = try await registry.callTool(name: "list_schemes", arguments: [:])

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-project"))
        #expect(capturedArgs.contains("/some/path.xcodeproj"))
    }

    @Test("Errors when no workspace or project available")
    func missingParams() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "list_schemes", arguments: [:])

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

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "xcodebuild: error: unable to open workspace")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "list_schemes", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Auto-sets scheme when exactly one found")
    func schemeAutoSet() async throws {
        let singleSchemeOutput = """
        Information about project "Solo":
            Schemes:
                SoloScheme
        """

        let session = SessionStore()
        await session.set(.project, value: "/path/to/Solo.xcodeproj")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(singleSchemeOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "list_schemes", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: scheme = SoloScheme"))
        } else {
            Issue.record("Expected success response")
        }

        let scheme = await session.get(.scheme)
        #expect(scheme == "SoloScheme")
    }

    @Test("Does not auto-set scheme when multiple found")
    func noSchemeAutoSetMultiple() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/MyApp.xcworkspace")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(workspaceOutput)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        _ = try await registry.callTool(name: "list_schemes", arguments: [:])

        let scheme = await session.get(.scheme)
        #expect(scheme == nil)
    }
}
