// Created by Jared Manfredi

import Foundation
import Testing
@testable import Core

@Suite("Native MCP diagnostics")
struct NativeMCPDiagnosticsTests {
    @Test("Finds the effective toolchain without starting native servers")
    func discoversWithoutConnecting() async throws {
        let executor = DiagnosticsExecutor(status: """
        {"running":false,"permission":{"enabled":true,"unsafeAlwaysAllowAllAgents":false},"openWorkspaces":[]}
        """)
        let lines = try await NativeMCPDiagnostics.run(executor: executor)
        #expect(lines.contains("[ok] Effective Xcode toolchain: /Applications/Selected Xcode.app/Contents/Developer/usr/bin/xcodebuild"))
        #expect(lines.contains("[ok] Native Xcode service: stopped"))
        #expect(lines.contains("[ok] Headless mode: enabled"))
        #expect(lines.contains("[ok] Allow-all-agents permission: disabled"))
        #expect(lines.contains { $0.contains("authorization and MCP tool schemas: not checked") })
        #expect(await executor.calls == [
            ["--find", "xcodebuild"], ["--find", "mcpbridge"],
            ["--find", "mcp-server"], ["--find", "lldb-mcp"],
            ["mcp-server", "status", "--format", "json"],
        ])
    }

    @Test("Older toolchains do not query an unavailable service")
    func missingServers() async throws {
        let executor = DiagnosticsExecutor(missingNativeTools: true)
        let lines = try await NativeMCPDiagnostics.run(executor: executor)
        #expect(lines.contains { $0.contains("mcpbridge: not found") })
        #expect(lines.contains { $0.contains("permissions: not queried") })
        #expect(await executor.calls.count == 4)
    }

    @Test("Malformed or failed status is unknown, never disabled or ready", arguments: [
        "not JSON", "{}", "{\"running\":false}",
        "{\"running\":true,\"permission\":{\"enabled\":\"true\"}}",
    ])
    func invalidStatus(status: String) async throws {
        let lines = try await NativeMCPDiagnostics.run(executor: DiagnosticsExecutor(status: status))
        #expect(lines.contains { $0.contains("permissions: unknown") })
        #expect(!lines.contains { $0.contains("Headless mode:") })
    }

    @Test("Nonzero status cannot be mistaken for valid JSON success")
    func failedStatus() async throws {
        let executor = DiagnosticsExecutor(status: """
        {"running":true,"permission":{"enabled":true,"unsafeAlwaysAllowAllAgents":false}}
        """, statusExitCode: 1)
        let lines = try await NativeMCPDiagnostics.run(executor: executor)
        #expect(lines.contains { $0.contains("permissions: unknown") })
        #expect(!lines.contains { $0.contains("service: running") })
    }

    @Test("Missing permission fields stay unknown and unrestricted mode is visible")
    func permissions() async throws {
        let partial = try await NativeMCPDiagnostics.run(executor: DiagnosticsExecutor(status: """
        {"running":true,"permission":{"enabled":false}}
        """))
        #expect(partial.contains("[ok] Headless mode: disabled"))
        #expect(partial.contains { $0.contains("Allow-all-agents permission: unknown") })

        let unrestricted = try await NativeMCPDiagnostics.run(executor: DiagnosticsExecutor(status: """
        {"running":true,"permission":{"enabled":true,"unsafeAlwaysAllowAllAgents":true}}
        """))
        #expect(unrestricted.contains("[--] Allow-all-agents permission: enabled"))
    }

    @Test("Transport failures stay unknown without printing raw server output")
    func statusThrows() async throws {
        let lines = try await NativeMCPDiagnostics.run(executor: DiagnosticsExecutor(throwsOnStatus: true))
        #expect(lines.contains { $0.contains("permissions: unknown (status query failed)") })
        #expect(!lines.joined().contains("sensitive-test-value"))
    }

    @Test("Cancellation stops diagnostics rather than reporting missing dependencies")
    func cancellation() async throws {
        let executor = DiagnosticsExecutor(cancelLookup: true)
        await #expect(throws: CancellationError.self) {
            try await NativeMCPDiagnostics.run(executor: executor)
        }
        #expect(await executor.calls.count == 1)
    }
}

private actor DiagnosticsExecutor: CommandExecuting {
    var calls: [[String]] = []
    let status: String
    let statusExitCode: Int32
    let missingNativeTools: Bool
    let throwsOnStatus: Bool
    let cancelLookup: Bool

    init(status: String = "{}", statusExitCode: Int32 = 0, missingNativeTools: Bool = false,
         throwsOnStatus: Bool = false, cancelLookup: Bool = false) {
        self.status = status
        self.statusExitCode = statusExitCode
        self.missingNativeTools = missingNativeTools
        self.throwsOnStatus = throwsOnStatus
        self.cancelLookup = cancelLookup
    }

    func execute(executable: String, arguments: [String], timeout: TimeInterval?,
                 environment: [String: String]?) async throws -> CommandResult {
        calls.append(arguments)
        #expect(executable == "/usr/bin/xcrun")
        #expect(timeout != nil && timeout! <= 10)
        #expect(environment == nil)
        if cancelLookup { throw CancellationError() }
        if arguments.first == "--find" {
            if missingNativeTools && arguments[1] != "xcodebuild" {
                return CommandResult(stdout: "", stderr: "not found", exitCode: 1)
            }
            return CommandResult(
                stdout: "/Applications/Selected Xcode.app/Contents/Developer/usr/bin/\(arguments[1])\n",
                stderr: "", exitCode: 0
            )
        }
        #expect(arguments == ["mcp-server", "status", "--format", "json"])
        if throwsOnStatus {
            throw ToolError(code: .timeout, message: "sensitive-test-value")
        }
        return CommandResult(stdout: status, stderr: "sensitive-test-value", exitCode: statusExitCode)
    }
}
