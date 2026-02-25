//
//  DebugBreakpointAddTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugBreakpointAddTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_add_breakpoint",
        description: "Add a breakpoint by symbol name or file:line location in the attached LLDB session.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
                "symbol": .init(
                    type: "string",
                    description: "Symbol name to break on (e.g. 'viewDidLoad')."
                ),
                "file": .init(
                    type: "string",
                    description: "Source file path for file:line breakpoint."
                ),
                "line": .init(
                    type: "number",
                    description: "Line number for file:line breakpoint."
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

            var symbol: String?
            if case .string(let s) = args["symbol"] { symbol = s }

            var file: String?
            if case .string(let f) = args["file"] { file = f }

            var line: Int?
            if case .int(let l) = args["line"] { line = l }

            let command: String
            if let symbol {
                command = "breakpoint set --name \(symbol)"
            } else if let file, let line {
                command = "breakpoint set --file \(file) --line \(line)"
            } else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Provide either 'symbol' or both 'file' and 'line'."
                ))
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
                message: "Failed to add breakpoint: \(error.localizedDescription)"
            ))
        }
    }
}
