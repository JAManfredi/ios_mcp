//
//  DebugAttachTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugAttachTool(
    with registry: ToolRegistry,
    session: SessionStore,
    debugSession: any DebugSessionManaging,
    concurrency: ConcurrencyPolicy
) async {
    let manifest = ToolManifest(
        name: "debug_attach",
        description: "Attach LLDB to a running process by PID or bundle ID. Returns a session ID for use with other debug tools. Falls back to session default for udid.",
        inputSchema: JSONSchema(
            properties: [
                "pid": .init(
                    type: "number",
                    description: "Process ID to attach to."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "Bundle identifier of the app to attach to."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .debugging
    )

    await registry.register(manifest: manifest) { args in
        do {
            var pid: Int?
            if case .int(let p) = args["pid"] {
                pid = p
            }

            var bundleID: String?
            if case .string(let b) = args["bundle_id"] {
                bundleID = b
            }

            guard pid != nil || bundleID != nil else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "At least one of 'pid' or 'bundle_id' is required."
                ))
            }

            var udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            } else {
                udid = await session.get(.simulatorUDID)
            }

            guard let resolvedUDID = udid else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No simulator UDID specified, and no session default is set. Run list_simulators first."
                ))
            }

            let lockKey = "lldb:\(pid ?? resolvedUDID.hashValue)"
            if let lockError = await concurrency.acquire(key: lockKey, owner: "debug_attach") {
                return .error(lockError)
            }

            do {
                let sessionID = try await debugSession.attach(
                    pid: pid,
                    bundleID: bundleID,
                    udid: resolvedUDID
                )

                var lines = [
                    "LLDB session attached.",
                    "Session ID: \(sessionID)",
                    "Simulator: \(resolvedUDID)",
                ]
                if let pid { lines.append("PID: \(pid)") }
                if let bundleID { lines.append("Bundle: \(bundleID)") }
                lines.append("\nUse debug_detach with this session_id to end the session.")

                return .success(ToolResult(content: lines.joined(separator: "\n")))
            } catch {
                await concurrency.release(key: lockKey)
                if let toolError = error as? ToolError { return .error(toolError) }
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to attach LLDB: \(error.localizedDescription)"
                ))
            }
        }
    }
}
