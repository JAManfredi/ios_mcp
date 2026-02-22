//
//  BootSimulatorToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("boot_simulator")
struct BootSimulatorToolTests {

    @Test("Boots simulator and sets session UDID")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(
            name: "boot_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("booted successfully"))
            #expect(result.content.contains("simulator_udid = AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("boot"))
        #expect(capturedArgs.contains("AAAA-1111"))

        let udid = await session.get(.simulatorUDID)
        #expect(udid == "AAAA-1111")
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "boot_simulator", arguments: [:])

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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(name: "boot_simulator", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when simctl boot fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "Unable to boot device in current state: Booted")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(
            name: "boot_simulator",
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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(
            name: "boot_simulator",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .resourceBusy)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Resolves name to UDID via simctl list")
    func nameResolution() async throws {
        let listJSON = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              {
                "udid": "RESOLVED-UUID",
                "name": "iPhone 16",
                "state": "Shutdown",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              }
            ]
          }
        }
        """

        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            if args.contains("-j") {
                return CommandResult(stdout: listJSON, stderr: "", exitCode: 0)
            }
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))

        let response = try await registry.callTool(
            name: "boot_simulator",
            arguments: ["name": .string("iPhone 16")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("RESOLVED-UUID"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("boot"))
        #expect(capturedArgs.contains("RESOLVED-UUID"))
    }
}
