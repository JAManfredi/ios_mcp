//
//  DebugTaskTreeTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerDebugTaskTreeTool(
    with registry: ToolRegistry,
    debugSession: any DebugSessionManaging
) async {
    let manifest = ToolManifest(
        name: "debug_task_tree",
        description: "Print the tree of Swift Concurrency tasks known to the attached LLDB session (`language swift task tree`, Xcode 27+). Use it to find stuck awaits, deadlocked actors, and leaked tasks; pause the process first with a breakpoint.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "The debug session ID returned by debug_attach."
                ),
            ],
            required: ["session_id"]
        ),
        category: .debugging,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let sessionID) = args["session_id"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter 'session_id'."
            ))
        }

        do {
            let output = try await debugSession.sendCommand(
                sessionID: sessionID,
                command: "language swift task tree",
                timeout: 30
            )

            // Older LLDB parses the command but has no such subcommand.
            if output.contains("is not a valid command") || output.contains("invalid command") {
                return .error(ToolError(
                    code: .dependencyMissing,
                    message: "This LLDB has no `language swift task tree`. It ships with Xcode 27 or later.",
                    details: output
                ))
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(ToolResult(content: trimmed.isEmpty ? "No Swift tasks reported." : trimmed))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to print the task tree: \(error.localizedDescription)"
            ))
        }
    }
}
