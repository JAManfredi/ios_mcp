//
//  CleanDerivedDataToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("clean_derived_data")
struct CleanDerivedDataToolTests {

    private func createTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-mcp-dd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Rejected without confirm")
    func rejectedWithoutConfirm() async throws {
        let tmp = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["derived_data_path": .string(tmp.path)]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("confirm: true"))
            // Directory should still exist — operation was blocked
            #expect(FileManager.default.fileExists(atPath: tmp.path))
        } else {
            Issue.record("Expected error response for missing confirm")
        }
    }

    @Test("Rejected when confirm is false")
    func rejectedWithConfirmFalse() async throws {
        let tmp = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["derived_data_path": .string(tmp.path), "confirm": .bool(false)]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("confirm: true"))
        } else {
            Issue.record("Expected error response for confirm: false")
        }
    }

    @Test("Deletes existing DerivedData directory with confirm: true")
    func happyPath() async throws {
        let tmp = try createTempDir()

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["derived_data_path": .string(tmp.path), "confirm": .bool(true)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Deleted DerivedData"))
            #expect(!FileManager.default.fileExists(atPath: tmp.path))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session derived_data_path")
    func sessionFallback() async throws {
        let tmp = try createTempDir()

        let session = SessionStore()
        await session.set(.derivedDataPath, value: tmp.path)

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["confirm": .bool(true)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Deleted DerivedData"))
            #expect(!FileManager.default.fileExists(atPath: tmp.path))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when path does not exist")
    func nonExistentPath() async throws {
        let fakePath = NSTemporaryDirectory() + "nonexistent-\(UUID().uuidString)"

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["derived_data_path": .string(fakePath), "confirm": .bool(true)]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("does not exist"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Explicit path takes precedence over session and default")
    func explicitPathPrecedence() async throws {
        let tmp = try createTempDir()

        let session = SessionStore()
        await session.set(.derivedDataPath, value: "/should/not/use/this")

        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "clean_derived_data",
            arguments: ["derived_data_path": .string(tmp.path), "confirm": .bool(true)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains(tmp.path))
            #expect(!FileManager.default.fileExists(atPath: tmp.path))
        } else {
            Issue.record("Expected success response")
        }
    }
}
