//
//  SwipeToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("swipe")
struct SwipeToolTests {

    @Test("Swipes element in given direction")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "udid": .string("AAAA-1111"),
                "direction": .string("up"),
                "accessibility_id": .string("scrollView"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Swiped up"))
            #expect(result.content.contains("AAAA-1111"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("swipe"))
        #expect(capturedArgs.contains("--direction"))
        #expect(capturedArgs.contains("up"))
        #expect(capturedArgs.contains("--identifier"))
        #expect(capturedArgs.contains("scrollView"))
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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "direction": .string("down"),
                "accessibility_id": .string("list"),
            ]
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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "direction": .string("up"),
                "accessibility_id": .string("list"),
            ]
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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "udid": .string("AAAA-1111"),
                "direction": .string("left"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No target"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when direction is missing")
    func missingDirection() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("list"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("direction"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when direction is invalid")
    func invalidDirection() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe")

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "udid": .string("AAAA-1111"),
                "direction": .string("diagonal"),
                "accessibility_id": .string("list"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("Invalid direction"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
