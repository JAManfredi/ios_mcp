//
//  DebugContinueTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugContinueTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_continue",
        description: "Resume execution in the attached LLDB session. Returns stop reason if a breakpoint is hit.",
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

            let output = try await debugSession.sendCommand(
                sessionID: sessionID,
                command: "continue",
                timeout: 300
            )

            return .success(ToolResult(content: output))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to continue: \(error.localizedDescription)"
            ))
        }
    }
}
