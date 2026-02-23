//
//  DebugStackTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugStackTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_stack",
        description: "Fetch the backtrace (stack trace) from the attached LLDB session.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
                "thread_id": .init(
                    type: "number",
                    description: "Thread ID to inspect. Defaults to the current thread."
                ),
            ],
            required: ["session_id"]
        ),
        category: .debugging,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        do {
            guard case .string(let sessionID) = args["session_id"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Missing required parameter 'session_id'."
                ))
            }

            let command: String
            if case .int(let threadID) = args["thread_id"] {
                command = "thread backtrace \(threadID)"
            } else {
                command = "bt"
            }

            let output = try await debugSession.sendCommand(
                sessionID: sessionID,
                command: command,
                timeout: 30
            )

            return .success(ToolResult(content: output))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to get stack trace: \(error.localizedDescription)"
            ))
        }
    }
}
