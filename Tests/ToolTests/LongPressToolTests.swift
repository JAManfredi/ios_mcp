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

private let mockDescribeUIJSON = """
[{
  "AXUniqueId": "cellItem",
  "AXLabel": "Cell",
  "frame": {"x": 50, "y": 200, "width": 300, "height": 50},
  "children": []
}]
"""

@Suite("long_press")
struct LongPressToolTests {

    @Test("Long presses element by accessibility_id")
    func happyPath() async throws {
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

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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

        let calls = await allCalls.allArgs
        #expect(calls.count == 2)
        #expect(calls[0].contains("describe-ui"))
        #expect(calls[1].contains("touch"))
        #expect(calls[1].contains("--down"))
        #expect(calls[1].contains("--up"))
        #expect(calls[1].contains("--delay"))
    }

    @Test("Long presses by coordinates without describe-ui call")
    func coordinatesDirect() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let allCalls = AllCallCapture()
        let executor = MockCommandExecutor { _, args in
            await allCalls.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "long_press",
            arguments: [
                "udid": .string("AAAA-1111"),
                "x": .int(100),
                "y": .int(200),
            ]
        )

        if case .success = response {
            let calls = await allCalls.allArgs
            #expect(calls.count == 1, "Should not call describe-ui when coordinates are provided")
            #expect(calls[0].contains("touch"))
            #expect(calls[0].contains("-x"))
            #expect(calls[0].contains("100"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let allCalls = AllCallCapture()
        let executor = MockCommandExecutor { _, args in
            await allCalls.capture(args)
            if args.contains("describe-ui") {
                return CommandResult(stdout: mockDescribeUIJSON, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "long_press",
            arguments: ["accessibility_id": .string("cellItem")]
        )

        if case .success = response {
            let calls = await allCalls.allArgs
            let touchCall = calls.last!
            #expect(touchCall.contains("SESSION-UDID"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no UDID available")
    func missingUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

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

    @Test("Passes custom duration to axe touch")
    func customDuration() async throws {
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

        await registerLongPressTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "long_press",
            arguments: [
                "udid": .string("AAAA-1111"),
                "accessibility_id": .string("cellItem"),
                "duration": .double(2.5),
            ]
        )

        if case .success = response {
            let calls = await allCalls.allArgs
            let touchCall = calls.last!
            #expect(touchCall.contains("--delay"))
            #expect(touchCall.contains("2.5"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
