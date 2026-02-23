//
//  TypeTextToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("type_text")
struct TypeTextToolTests {

    @Test("Types text on simulator with tap-first targeting")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let allCalls = AllCallCapture()
        let executor = MockCommandExecutor { _, args in
            await allCalls.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerTypeTextTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "type_text",
            arguments: [
                "udid": .string("AAAA-1111"),
                "text": .string("hello world"),
                "accessibility_id": .string("searchField"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Typed text"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let calls = await allCalls.allArgs
        #expect(calls.count == 2, "Should tap first, then type")

        // First call: tap to focus
        let tapCall = calls[0]
        #expect(tapCall.contains("tap"))
        #expect(tapCall.contains("--id"))
        #expect(tapCall.contains("searchField"))

        // Second call: type text (positional arg)
        let typeCall = calls[1]
        #expect(typeCall.contains("type"))
        #expect(typeCall.contains("hello world"))
        #expect(!typeCall.contains("--text"))
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

        await registerTypeTextTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "type_text",
            arguments: ["text": .string("test")]
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

        await registerTypeTextTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "type_text",
            arguments: ["text": .string("hello")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when text is missing")
    func missingText() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerTypeTextTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "type_text",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("text"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Targeting is optional — types into focused field")
    func noTargetOk() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerTypeTextTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "type_text",
            arguments: [
                "udid": .string("AAAA-1111"),
                "text": .string("no target"),
            ]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("type"))
            #expect(capturedArgs.contains("no target"))
            #expect(!capturedArgs.contains("--text"))
            #expect(!capturedArgs.contains("--id"))
            #expect(!capturedArgs.contains("--label"))
            #expect(!capturedArgs.contains("-x"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
