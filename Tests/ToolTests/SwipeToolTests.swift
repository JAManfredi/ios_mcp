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

private let mockDescribeUIJSON = """
[{
  "AXUniqueId": "scrollView",
  "AXLabel": "Scroll",
  "frame": {"x": 0, "y": 100, "width": 400, "height": 600},
  "children": []
}]
"""

@Suite("swipe")
struct SwipeToolTests {

    @Test("Swipes with gesture preset when no target provided")
    func gesturePreset() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "udid": .string("AAAA-1111"),
                "direction": .string("up"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Swiped up"))
        } else {
            Issue.record("Expected success response")
        }

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.contains("gesture"))
        #expect(capturedArgs.contains("scroll-up"))
    }

    @Test("Swipes with coordinates when accessibility target provided")
    func targetedSwipe() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let allCalls = AllCallCapture()
        let executor = MockCommandExecutor { _, args in
            await allCalls.capture(args)
            if args.contains("describe-ui") {
                return CommandResult(stdout: mockDescribeUIJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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
        } else {
            Issue.record("Expected success response")
        }

        let calls = await allCalls.allArgs
        #expect(calls.count == 2)
        #expect(calls[0].contains("describe-ui"))
        #expect(calls[1].contains("swipe"))
        #expect(calls[1].contains("--start-x"))
        #expect(calls[1].contains("--end-y"))
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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "direction": .string("down"),
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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "swipe",
            arguments: [
                "direction": .string("up"),
            ]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Errors when direction is missing")
    func missingDirection() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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

        await registerSwipeTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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
