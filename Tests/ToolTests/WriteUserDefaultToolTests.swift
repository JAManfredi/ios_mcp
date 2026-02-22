//
//  WriteUserDefaultToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("write_user_default")
struct WriteUserDefaultToolTests {

    @Test("Writes string value with default type")
    func happyPathString() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerWriteUserDefaultTool(with: registry, session: session, executor: executor)

        let response = try await registry.callTool(
            name: "write_user_default",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
                "key": .string("theme"),
                "value": .string("dark"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("theme"))
            #expect(result.content.contains("dark"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("-string"))
        #expect(capturedArgs.contains("dark"))
        #expect(capturedArgs.contains("theme"))
        #expect(capturedArgs.contains("com.example.MyApp"))
    }

    @Test("Writes bool value with explicit type")
    func happyPathBool() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerWriteUserDefaultTool(with: registry, session: session, executor: executor)

        let response = try await registry.callTool(
            name: "write_user_default",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
                "key": .string("darkMode"),
                "value": .string("true"),
                "type": .string("bool"),
            ]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("-bool"))
            #expect(capturedArgs.contains("true"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when domain is missing")
    func missingDomain() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerWriteUserDefaultTool(with: registry, session: session, executor: executor)

        let response = try await registry.callTool(
            name: "write_user_default",
            arguments: [
                "udid": .string("AAAA-1111"),
                "key": .string("theme"),
                "value": .string("dark"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("domain"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when key is missing")
    func missingKey() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerWriteUserDefaultTool(with: registry, session: session, executor: executor)

        let response = try await registry.callTool(
            name: "write_user_default",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
                "value": .string("dark"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("key"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when value is missing")
    func missingValue() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerWriteUserDefaultTool(with: registry, session: session, executor: executor)

        let response = try await registry.callTool(
            name: "write_user_default",
            arguments: [
                "udid": .string("AAAA-1111"),
                "domain": .string("com.example.MyApp"),
                "key": .string("theme"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("value"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
