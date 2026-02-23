//
//  LintToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("lint")
struct LintToolTests {

    @Test("Returns lint output on clean run")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let lintJSON = "[{\"rule_id\":\"trailing_whitespace\"}]"
        let executor = MockCommandExecutor { _, _ in
            CommandResult(stdout: lintJSON, stderr: "", exitCode: 0)
        }

        await registerLintTool(with: registry, session: session, executor: executor, swiftLintPath: "/usr/local/bin/swiftlint", validator: testValidator())

        let response = try await registry.callTool(
            name: "lint",
            arguments: ["path": .string("/path/to/project")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("trailing_whitespace"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Exit code 1 (violations) is still success")
    func violationsStillSuccess() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let lintOutput = "[{\"rule_id\":\"line_length\",\"severity\":\"warning\"}]"
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: lintOutput, stderr: "", exitCode: 1)
        }

        await registerLintTool(with: registry, session: session, executor: executor, swiftLintPath: "/usr/local/bin/swiftlint", validator: testValidator())

        let response = try await registry.callTool(
            name: "lint",
            arguments: ["path": .string("/path/to/project")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("line_length"))
        } else {
            Issue.record("Expected success response even with violations")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("lint"))
        #expect(capturedArgs.contains("--path"))
        #expect(capturedArgs.contains("/path/to/project"))
        #expect(capturedArgs.contains("--reporter"))
        #expect(capturedArgs.contains("json"))
    }

    @Test("Falls back to session workspace path")
    func sessionFallbackPath() async throws {
        let session = SessionStore()
        await session.set(.workspace, value: "/session/workspace")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "[]", stderr: "", exitCode: 0)
        }

        await registerLintTool(with: registry, session: session, executor: executor, swiftLintPath: "/usr/local/bin/swiftlint", validator: testValidator())

        let response = try await registry.callTool(
            name: "lint",
            arguments: [:]
        )

        if case .success = response {
            let capturedArgs = await capture.lastArgs
            #expect(capturedArgs.contains("/session/workspace"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no path and no session workspace or project")
    func missingPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerLintTool(with: registry, session: session, executor: executor, swiftLintPath: "/usr/local/bin/swiftlint", validator: testValidator())

        let response = try await registry.callTool(
            name: "lint",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("path"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
