//
//  ReadUserDefaultsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("read_user_defaults")
struct ReadUserDefaultsToolTests {

    @Test("Reads specific key for domain")
    func happyPathDomainAndKey() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "dark", stderr: "", exitCode: 0)
        }

        await registerReadUserDefaultsTool(with: registry, session: session, executor: executor, validator: testValidator())

        let response = try await registry.callTool(
            name: "read_user_defaults",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
                "key": .string("theme"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content == "dark")
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("simctl"))
        #expect(capturedArgs.contains("spawn"))
        #expect(capturedArgs.contains("AAAA-1111"))
        #expect(capturedArgs.contains("defaults"))
        #expect(capturedArgs.contains("read"))
        #expect(capturedArgs.contains("com.example.MyApp"))
        #expect(capturedArgs.contains("theme"))
    }

    @Test("Reads all keys when no key provided")
    func happyPathDomainOnly() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let plistOutput = "{\n    theme = dark;\n    fontSize = 14;\n}"
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: plistOutput, stderr: "", exitCode: 0)
        }

        await registerReadUserDefaultsTool(with: registry, session: session, executor: executor, validator: testValidator())

        let response = try await registry.callTool(
            name: "read_user_defaults",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("theme"))
            #expect(result.content.contains("fontSize"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(!capturedArgs.contains("theme"))
        #expect(capturedArgs.last == "com.example.MyApp")
    }

    @Test("Falls back to session UDID")
    func sessionFallbackUDID() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "value", stderr: "", exitCode: 0)
        }

        await registerReadUserDefaultsTool(with: registry, session: session, executor: executor, validator: testValidator())

        let response = try await registry.callTool(
            name: "read_user_defaults",
            arguments: [
                "domain": .string("com.example.MyApp"),
                "key": .string("theme"),
            ]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when domain is missing")
    func missingDomain() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerReadUserDefaultsTool(with: registry, session: session, executor: executor, validator: testValidator())

        let response = try await registry.callTool(
            name: "read_user_defaults",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("domain"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
