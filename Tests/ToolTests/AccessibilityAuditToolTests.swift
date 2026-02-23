//
//  AccessibilityAuditToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("accessibility_audit")
struct AccessibilityAuditToolTests {

    @Test("Returns audit output")
    func happyPath() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let auditOutput = "Audit complete: 2 issues found\n- Missing label on button\n- Low contrast text"
        let executor = MockCommandExecutor { _, _ in
            CommandResult(stdout: auditOutput, stderr: "", exitCode: 0)
        }

        await registerAccessibilityAuditTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "accessibility_audit",
            arguments: ["udid": .string("AAAA-1111")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Audit complete"))
            #expect(result.content.contains("Missing label"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Falls back to session UDID")
    func sessionFallbackUDID() async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")

        let registry = ToolRegistry()
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "Audit complete: 0 issues", stderr: "", exitCode: 0)
        }

        await registerAccessibilityAuditTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "accessibility_audit",
            arguments: [:]
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

        await registerAccessibilityAuditTool(with: registry, session: session, executor: executor, axePath: "/usr/local/bin/axe", validator: testValidator())

        let response = try await registry.callTool(
            name: "accessibility_audit",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No simulator UDID"))
        } else {
            Issue.record("Expected error response")
        }
    }
}
