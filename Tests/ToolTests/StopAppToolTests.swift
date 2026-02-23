//
//  StopAppToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("stop_app")
struct StopAppToolTests {

    @Test("Stops app on simulator")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "stop_app",
            arguments: [
                "udid": .string("AAAA-1111"),
                "bundle_id": .string("com.example.app"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Stopped com.example.app"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("terminate"))
        #expect(capturedArgs.contains("AAAA-1111"))
        #expect(capturedArgs.contains("com.example.app"))
    }

    @Test("Falls back to session defaults")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")
        await session.set(.bundleID, value: "com.session.app")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "stop_app", arguments: [:])

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("SESSION-UDID"))
            #expect(capturedArgs.contains("com.session.app"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        await session.set(.bundleID, value: "com.example.app")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "stop_app", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no bundle_id available")
    func missingBundleID() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "stop_app",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No bundle_id"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when simctl terminate fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "An error was encountered processing the command")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "stop_app",
            arguments: [
                "udid": .string("AAAA-1111"),
                "bundle_id": .string("com.example.app"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
