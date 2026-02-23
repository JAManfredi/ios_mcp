//
//  TapToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("tap")
struct TapToolTests {

    @Test("Taps element by accessibility_id")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerTapTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "tap",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("loginButton"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Tapped"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("tap"))
        #expect(capturedArgs.contains("--id"))
        #expect(capturedArgs.contains("loginButton"))
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

        await registerTapTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "tap",
            arguments: ["accessibility_id": .string("btn")]
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

        await registerTapTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "tap",
            arguments: ["accessibility_id": .string("btn")]
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

        await registerTapTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "tap",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No target"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when axe tap fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "element not found")

        await registerTapTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "tap",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("btn"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
