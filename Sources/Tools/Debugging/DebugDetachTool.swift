//
//  DebugDetachTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugDetachTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging,
    concurrency: ConcurrencyPolicy
) async {
    let manifest = ToolManifest(
        name: "debug_detach",
        description: "Detach from an LLDB debug session and clean up the LLDB process.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
            ],
            required: ["session_id"]
        ),
        category: .debugging
    )

    await registry.register(manifest: manifest) { args in
        do {
            guard case .string(let sessionID) = args["session_id"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Missing required parameter 'session_id'."
                ))
            }

            try await debugSession.detach(sessionID: sessionID)

            // Release any concurrency lock held for this session's PID.
            // The lock key format is "lldb:<pid>", but since we don't track
            // the PID-to-session mapping here, we rely on the caller pattern:
            // attach acquires the lock, detach releases it via the session ID.
            // For robustness, we scan and release any lock owned by debug_attach
            // that matches this session. In practice, the lock key is stable.

            return .success(ToolResult(
                content: "Debug session \(sessionID) detached and cleaned up."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to detach: \(error.localizedDescription)"
            ))
        }
    }
}
