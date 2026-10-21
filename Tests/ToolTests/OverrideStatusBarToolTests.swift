//
//  OverrideStatusBarToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

@Suite("override_status_bar")
struct OverrideStatusBarToolTests {
    @Test(arguments: ["battery_level", "cellular_bars", "wifi_bars", "time", "operator_name", "clear", "preset"])
    func rejectsWrongTypesEvenWithPreset(key: String) async throws {
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        await registerOverrideStatusBarTool(with: registry, session: SessionStore(), executor: executor, validator: testValidator())
        var args: [String: Value] = ["udid": .string("AAAA-1111"), "preset": .string("screenshot")]
        args[key] = ["battery_level", "cellular_bars", "wifi_bars"].contains(key) ? .string("100") : .int(1)
        guard case .error(let error) = try await registry.callTool(name: "override_status_bar", arguments: args) else {
            Issue.record("Expected invalid input"); return
        }
        #expect(error.code == .invalidInput)
        #expect(await capture.lastArgs.isEmpty)
    }

    @Test(arguments: [Double.nan, .infinity, 1e100, 1.5])
    func rejectsUnrepresentableNumbers(number: Double) async throws {
        let registry = ToolRegistry()
        await registerOverrideStatusBarTool(with: registry, session: SessionStore(), executor: MockCommandExecutor.succeedingWith(""), validator: testValidator())
        let response = try await registry.callTool(name: "override_status_bar", arguments: ["udid": .string("AAAA-1111"), "preset": .string("screenshot"), "battery_level": .double(number)])
        guard case .error(let error) = response else { Issue.record("Expected invalid input"); return }
        #expect(error.code == .invalidInput)
    }

    @Test("Overrides status bar with time")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: [
                "udid": .string("AAAA-1111"),
                "time": .string("9:41"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("overridden"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("status_bar"))
        #expect(capturedArgs.contains("override"))
        #expect(capturedArgs.contains("--time"))
        #expect(capturedArgs.contains("9:41"))
    }

    @Test("Clears status bar overrides")
    func clearMode() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: [
                "udid": .string("AAAA-1111"),
                "clear": .bool(true),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("cleared"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("status_bar"))
        #expect(capturedArgs.contains("clear"))
    }

    @Test("Overrides with battery level")
    func batteryLevel() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: [
                "udid": .string("AAAA-1111"),
                "battery_level": .int(75),
            ]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("--batteryLevel"))
            #expect(capturedArgs.contains("75"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no overrides provided")
    func noOverrides() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("At least one"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: ["time": .string("9:41")]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: ["time": .string("9:41")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when simctl fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "Error")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: [
                "udid": .string("AAAA-1111"),
                "time": .string("9:41"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
