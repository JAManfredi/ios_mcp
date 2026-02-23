//
//  SnapshotUIToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("snapshot_ui")
struct SnapshotUIToolTests {

    @Test("Returns accessibility tree content")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let treeOutput = """
        {"type": "Window", "children": [{"type": "Button", "label": "OK"}]}
        """
        let executor = MockCommandExecutor.succeedingWith(treeOutput)

        await registerSnapshotUITool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "snapshot_ui",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Window"))
            #expect(result.content.contains("Button"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "{}", stderr: "", exitCode: 0)
        }

        await registerSnapshotUITool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(name: "snapshot_ui", arguments: [:])

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

        await registerSnapshotUITool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(name: "snapshot_ui", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when axe describe-ui fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "axe: device not found")

        await registerSnapshotUITool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "snapshot_ui",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
