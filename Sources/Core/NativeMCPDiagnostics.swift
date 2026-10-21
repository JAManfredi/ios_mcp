// Created by Jared Manfredi

import Foundation

/// Read-only discovery. Never starts a bridge, opens a workspace, or changes permissions.
public enum NativeMCPDiagnostics {
    public static func run(executor: any CommandExecuting) async throws -> [String] {
        var lines = ["\nNative Xcode MCP (optional; existing ios-mcp backends remain active)"]
        var found: Set<String> = []

        // xcrun honors DEVELOPER_DIR as well as xcode-select. A version number alone
        // cannot establish that a tool is present in the effective toolchain.
        for tool in ["xcodebuild", "mcpbridge", "mcp-server", "lldb-mcp"] {
            try Task.checkCancellation()
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun", arguments: ["--find", tool],
                    timeout: 5, environment: nil
                )
                let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.succeeded, path.hasPrefix("/"), !path.contains("\n") {
                    found.insert(tool)
                    let label = tool == "xcodebuild" ? "Effective Xcode toolchain" : tool
                    lines.append("[ok] \(label): \(Redactor.redact(path))")
                } else {
                    lines.append("[--] \(tool): not found by xcrun (or lookup failed)")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lines.append("[--] \(tool): lookup failed; availability unknown")
            }
        }

        if found.contains("mcp-server") {
            do {
                try Task.checkCancellation()
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["mcp-server", "status", "--format", "json"],
                    timeout: 10, environment: nil
                )
                if result.succeeded,
                   let status = try? JSONDecoder().decode(ServerStatus.self, from: Data(result.stdout.utf8)) {
                    lines.append("[ok] Native Xcode service: \(status.running ? "running" : "stopped")")
                    lines.append("[ok] Headless mode: \(status.permission.enabled ? "enabled" : "disabled")")
                    if let unrestricted = status.permission.unsafeAlwaysAllowAllAgents {
                        lines.append("[\(unrestricted ? "--" : "ok")] Allow-all-agents permission: \(unrestricted ? "enabled" : "disabled")")
                    } else {
                        lines.append("[--] Allow-all-agents permission: unknown (not reported)")
                    }
                } else {
                    lines.append("[--] Native Xcode service and permissions: unknown (status failed or JSON format unsupported)")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lines.append("[--] Native Xcode service and permissions: unknown (status query failed)")
            }
        } else {
            lines.append("[--] Native Xcode service and permissions: not queried (mcp-server unavailable)")
        }

        try Task.checkCancellation()
        lines.append("[--] Agent/folder authorization and MCP tool schemas: not checked (requires an explicit connection)")
        lines.append("[--] Native UI and LLDB compatibility: not established by binary availability; see docs/native-mcp-compatibility.md")
        return lines
    }

    private struct ServerStatus: Decodable {
        let running: Bool
        let permission: Permission

        struct Permission: Decodable {
            let enabled: Bool
            let unsafeAlwaysAllowAllAgents: Bool?
        }
    }
}
