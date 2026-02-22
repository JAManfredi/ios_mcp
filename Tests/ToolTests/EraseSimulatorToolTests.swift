//
//  EraseSimulatorToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("erase_simulator")
struct EraseSimulatorToolTests {

    @Test("Erases simulator")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(
            name: "erase_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("erased successfully"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("erase"))
        #expect(capturedArgs.contains("AAAA-1111"))
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        _ = try await registry.callTool(name: "erase_simulator", arguments: [:])

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("SESSION-UDID"))
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(name: "erase_simulator", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when simctl erase fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "Unable to erase contents and settings: device is booted")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(
            name: "erase_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns resource busy when lock held")
    func resourceBusy() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let concurrency = ConcurrencyPolicy()
        let executor = MockCommandExecutor.succeedingWith("")

        _ = await concurrency.acquire(key: "simulator:AAAA-1111", owner: "other_operation")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency)

        let response = try await registry.callTool(
            name: "erase_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .resourceBusy)
        } else {
            Issue.record("Expected error response")
        }
    }
}
