//
//  ScreenshotToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("screenshot")
struct ScreenshotToolTests {

    @Test("Captures screenshot and returns artifact")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let artifacts = ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-artifacts-\(UUID().uuidString)"))

        // 1x1 red PNG
        let pngData = makeMinimalPNG()
        let executor = MockCommandExecutor { _, args in
            // Write fake PNG to the temp path (last argument)
            if let path = args.last, path.hasSuffix(".png") {
                try pngData.write(to: URL(fileURLWithPath: path))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "screenshot",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Screenshot captured"))
            #expect(result.content.contains("AAAA-1111"))
            #expect(result.artifacts.count == 1)
            #expect(result.artifacts.first?.mimeType == "image/png")
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallback() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let artifacts = ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-artifacts-\(UUID().uuidString)"))
        let pngData = makeMinimalPNG()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            if let path = args.last, path.hasSuffix(".png") {
                try pngData.write(to: URL(fileURLWithPath: path))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "screenshot", arguments: [:])

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

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(name: "screenshot", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Returns error when simctl screenshot fails")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "No devices found")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "screenshot",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("inline=false returns path without inlineArtifacts")
    func metadataOnlyMode() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let artifacts = ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-artifacts-\(UUID().uuidString)"))
        let pngData = makeMinimalPNG()
        let executor = MockCommandExecutor { _, args in
            if let path = args.last, path.hasSuffix(".png") {
                try pngData.write(to: URL(fileURLWithPath: path))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "screenshot",
            arguments: ["udid": .string("AAAA-1111"), "inline": .bool(false)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Screenshot captured"))
            #expect(result.artifacts.count == 1)
            #expect(!result.inlineArtifacts, "inlineArtifacts should be false when inline=false")
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Default (no inline param) returns inlineArtifacts false")
    func inlineDefaultFalse() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let artifacts = ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-artifacts-\(UUID().uuidString)"))
        let pngData = makeMinimalPNG()
        let executor = MockCommandExecutor { _, args in
            if let path = args.last, path.hasSuffix(".png") {
                try pngData.write(to: URL(fileURLWithPath: path))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "screenshot",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(!result.inlineArtifacts, "inlineArtifacts should be false by default")
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Passes correct arguments to simctl")
    func argShape() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let artifacts = ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-artifacts-\(UUID().uuidString)"))
        let pngData = makeMinimalPNG()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            if let path = args.last, path.hasSuffix(".png") {
                try pngData.write(to: URL(fileURLWithPath: path))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        _ = try await registry.callTool(
            name: "screenshot",
            arguments: ["udid": .string("TEST-UDID")]
        )

        let capturedArgs = await capture.lastArgs
        #expect(capturedArgs.count == 5)
        #expect(capturedArgs[0] == "simctl")
        #expect(capturedArgs[1] == "io")
        #expect(capturedArgs[2] == "TEST-UDID")
        #expect(capturedArgs[3] == "screenshot")
        #expect(capturedArgs[4].hasSuffix(".png"))
    }
}

// MARK: - Helpers

/// Generates a minimal valid 1x1 white PNG (67 bytes).
private func makeMinimalPNG() -> Data {
    Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}
