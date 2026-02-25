//
//  DebugLLDBCommandTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Logging
import MCP

func registerDebugLLDBCommandTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let logger = Logger(label: "ios-mcp.lldb-audit")

    let manifest = ToolManifest(
        name: "debug_run_command",
        description: "Execute an arbitrary LLDB command in the attached session. Commands are checked against a denylist for safety. Set allow_unsafe to bypass the denylist (response will be marked accordingly).",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
                "command": .init(
                    type: "string",
                    description: "The LLDB command to execute."
                ),
                "allow_unsafe": .init(
                    type: "boolean",
                    description: "If true, bypass the command denylist. Default false."
                ),
            ],
            required: ["session_id", "command"]
        ),
        category: .debugging,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        do {
            guard case .string(let sessionID) = args["session_id"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Missing required parameter 'session_id'."
                ))
            }

            guard case .string(let command) = args["command"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Missing required parameter 'command'."
                ))
            }

            var allowUnsafe = false
            if case .bool(let flag) = args["allow_unsafe"] {
                allowUnsafe = flag
            }

            logger.info("[\(sessionID)] \(command) (unsafe: \(allowUnsafe))")

            if !allowUnsafe {
                let denyResult = checkDenylist(command: command)
                if case .denied(let reason, let suggestion) = denyResult {
                    return .error(ToolError(
                        code: .commandDenied,
                        message: "Command denied: \(reason). \(suggestion)"
                    ))
                }
            }

            let output = try await debugSession.sendCommand(
                sessionID: sessionID,
                command: command,
                timeout: 30
            )

            if allowUnsafe {
                return .success(ToolResult(
                    content: "[UNSAFE] Denylist bypassed.\n\(output)",
                    unsafeCommandExecuted: true
                ))
            }

            return .success(ToolResult(content: output))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to execute command: \(error.localizedDescription)"
            ))
        }
    }
}
