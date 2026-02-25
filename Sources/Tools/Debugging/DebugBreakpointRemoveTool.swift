//
//  DebugBreakpointRemoveTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugBreakpointRemoveTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_remove_breakpoint",
        description: "Remove a breakpoint by its ID from the attached LLDB session.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
                "breakpoint_id": .init(
                    type: "number",
                    description: "The breakpoint ID to remove."
                ),
            ],
            required: ["session_id", "breakpoint_id"]
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

            guard case .int(let breakpointID) = args["breakpoint_id"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Missing required parameter 'breakpoint_id'."
                ))
            }

            let output = try await debugSession.sendCommand(
                sessionID: sessionID,
                command: "breakpoint delete \(breakpointID)",
                timeout: 30
            )

            return .success(ToolResult(content: output))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to remove breakpoint: \(error.localizedDescription)"
            ))
        }
    }
}
