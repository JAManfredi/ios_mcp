//
//  DebugVariablesTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

func registerDebugVariablesTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_variables",
        description: "Fetch frame variables from the attached LLDB session.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
                "frame_index": .init(
                    type: "number",
                    description: "Frame index to inspect. Defaults to the current frame."
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

            var commands: [String] = []
            if case .int(let frameIndex) = args["frame_index"] {
                commands.append("frame select \(frameIndex)")
            }
            commands.append("frame variable")

            var outputParts: [String] = []
            for command in commands {
                let output = try await debugSession.sendCommand(
                    sessionID: sessionID,
                    command: command,
                    timeout: 30
                )
                outputParts.append(output)
            }

            return .success(ToolResult(content: outputParts.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to get variables: \(error.localizedDescription)"
            ))
        }
    }
}
