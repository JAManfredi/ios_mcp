//
//  ShowSessionToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("show_session")
struct ShowSessionToolTests {

    @Test("Shows all session defaults")
    func happyPath() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")
        await session.set(.bundleID, value: "com.example.app")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "show_session", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("simulator_udid = SIM-1111"))
            #expect(result.content.contains("bundle_id = com.example.app"))
            #expect(result.content.contains("scheme = MyApp"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Shows empty state when no defaults set")
    func emptySession() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(name: "show_session", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("No session defaults"))
        } else {
            Issue.record("Expected success response")
        }
    }
}
