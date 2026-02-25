//
//  SwiftPackageInitToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("swift_package_init")
struct SwiftPackageInitToolTests {

    @Test("Initializes package with type and name")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { exec, args in
            if exec == "/usr/bin/swift" {
                await capture.capture(args)
                return CommandResult(stdout: "Creating executable package: MyTool", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_init",
            arguments: [
                "path": .string("/tmp/NewPackage"),
                "type": .string("executable"),
                "name": .string("MyTool"),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Swift package initialized"))
            #expect(result.content.contains("/tmp/NewPackage"))
        } else {
            Issue.record("Expected success response")
        }

        let args = await capture.lastArgs
        #expect(args.contains("init"))
        #expect(args.contains("--type"))
        #expect(args.contains("executable"))
        #expect(args.contains("--name"))
        #expect(args.contains("MyTool"))
    }

    @Test("Errors when path is missing")
    func missingPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor { _, args in
            if args.contains("-j") { return CommandResult(stdout: validatorSimctlJSON, stderr: "", exitCode: 0) }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let response = try await registry.callTool(
            name: "swift_package_init",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
