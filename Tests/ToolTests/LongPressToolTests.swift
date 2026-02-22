//
//  LongPressToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("long_press")
struct LongPressToolTests {

    @Test("Long presses element by accessibility_id")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "long_press",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("cellItem"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Long pressed"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("longpress"))
        #expect(capturedArgs.contains("--identifier"))
        #expect(capturedArgs.contains("cellItem"))
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

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "long_press",
            arguments: ["accessibility_id": .string("item")]
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

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "long_press",
            arguments: ["accessibility_id": .string("item")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when no target provided")
    func missingTarget() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "long_press",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No target"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Passes custom duration to axe")
    func customDuration() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "long_press",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("item"),
                "duration": .double(2.5),
            ]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("--duration"))
            #expect(capturedArgs.contains("2.5"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
