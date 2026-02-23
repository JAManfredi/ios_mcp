//
//  OpenSimulatorToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("open_simulator")
struct OpenSimulatorToolTests {

    @Test("Opens Simulator without booting when no UDID")
    func happyPathNoUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { executable, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "open_simulator",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Opened Simulator.app"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-a"))
        #expect(capturedArgs.contains("Simulator"))
    }

    @Test("Boots then opens when UDID provided")
    func happyPathWithUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        var allCalls: [(String, [String])] = []
        let callTracker = CallTracker()
        let executor = MockCommandExecutor { executable, args in
            await callTracker.record(executable: executable, args: args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "open_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Booted simulator AAAA-1111"))
            #expect(result.content.contains("Simulator.app"))
        } else {
            Issue.record("Expected success response")
        }

        let calls = await callTracker.calls
        // First call: boot
        #expect(calls.count >= 2)
        #expect(calls[0].args.contains("boot"))
        #expect(calls[0].args.contains("AAAA-1111"))
        // Second call: open
        #expect(calls[1].args.contains("Simulator"))
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let callTracker = CallTracker()
        let executor = MockCommandExecutor { executable, args in
            await callTracker.record(executable: executable, args: args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "open_simulator",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }

        let calls = await callTracker.calls
        #expect(calls[0].args.contains("SESSION-UDID"))
    }

    @Test("Succeeds when boot reports already booted")
    func alreadyBooted() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { executable, args in
            if args.contains("boot") {
                return CommandResult(stdout: "", stderr: "Unable to boot device in current state: Booted", exitCode: 149)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "open_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Simulator.app"))
        } else {
            Issue.record("Expected success response")
        }
    }
}

// MARK: - Test Helpers

/// Actor-based tracker for recording multiple command invocations in order.
private actor CallTracker {
    struct Call {
        let executable: String
        let args: [String]
    }

    private(set) var calls: [Call] = []

    func record(executable: String, args: [String]) {
        calls.append(Call(executable: executable, args: args))
    }
}
