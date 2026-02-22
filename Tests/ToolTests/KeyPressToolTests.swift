//
//  KeyPressToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("key_press")
struct KeyPressToolTests {

    @Test("Presses key on simulator")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerKeyPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "key_press",
            arguments: [
                "udid": .string("AAAA-1111"),
                "key": .string("return"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Pressed key"))
            #expect(result.content.contains("return"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("key"))
        #expect(capturedArgs.contains("--key"))
        #expect(capturedArgs.contains("return"))
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

        await registerKeyPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "key_press",
            arguments: ["key": .string("escape")]
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

        await registerKeyPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "key_press",
            arguments: ["key": .string("return")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when key is missing")
    func missingKey() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerKeyPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "key_press",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("key"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
