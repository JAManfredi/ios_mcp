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

            if let lockKey = await debugSession.removeLockKey(sessionID: sessionID) {
                await concurrency.release(key: lockKey)
            }

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
