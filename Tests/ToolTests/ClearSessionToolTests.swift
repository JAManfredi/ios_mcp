//
//  ClearSessionToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("clear_session")
struct ClearSessionToolTests {

    @Test("Clears all session defaults")
    func clearAll() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")
        await session.set(.bundleID, value: "com.example.app")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(name: "clear_session", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("All session defaults cleared"))
        } else {
            Issue.record("Expected success response")
        }

        let defaults = await session.allDefaults()
        #expect(defaults.isEmpty)
    }

    @Test("Clears specific keys")
    func clearSpecificKeys() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SIM-1111")
        await session.set(.bundleID, value: "com.example.app")
        await session.set(.scheme, value: "MyApp")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clear_session",
            arguments: ["keys": .string("simulator_udid, bundle_id")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("simulator_udid"))
            #expect(result.content.contains("bundle_id"))
        } else {
            Issue.record("Expected success response")
        }

        let udid = await session.get(.simulatorUDID)
        let bundleID = await session.get(.bundleID)
        let scheme = await session.get(.scheme)
        #expect(udid == nil)
        #expect(bundleID == nil)
        #expect(scheme == "MyApp")
    }

    @Test("Errors on invalid key name")
    func invalidKeyName() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clear_session",
            arguments: ["keys": .string("fake_key")]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("Unknown session key"))
            #expect(error.message.contains("fake_key"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
