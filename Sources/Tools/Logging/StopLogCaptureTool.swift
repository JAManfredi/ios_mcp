//
//  StopLogCaptureTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStopLogCaptureTool(
    with registry: ToolRegistry,
    logCapture: any LogCapturing
) async {
    let manifest = ToolManifest(
        name: "stop_log_capture",
        description: "Stop a running log capture session and retrieve captured log entries. Requires the session_id from start_log_capture.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "Session ID returned by start_log_capture."
                ),
                "max_entries": .init(
                    type: "number",
                    description: "Limit the number of returned entries (returns the most recent). Default: all."
                ),
            ],
            required: ["session_id"]
        ),
        category: .logging
    )

    await registry.register(manifest: manifest) { args in
        do {
            guard case .string(let sessionID) = args["session_id"] else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "session_id is required."
                ))
            }

            let maxEntries: Int?
            if case .int(let limit) = args["max_entries"] {
                maxEntries = limit
            } else {
                maxEntries = nil
            }

            let result = try await logCapture.stopCapture(sessionID: sessionID)

            let entries: [LogEntry]
            if let maxEntries, maxEntries < result.entries.count {
                entries = Array(result.entries.suffix(maxEntries))
            } else {
                entries = result.entries
            }

            var lines: [String] = [
                "Log capture stopped.",
                "Entries returned: \(entries.count)",
                "Total entries received: \(result.totalEntriesReceived)",
            ]

            if result.droppedEntryCount > 0 {
                lines.append("Dropped entries (buffer overflow): \(result.droppedEntryCount)")
            }

            lines.append("")

            for entry in entries {
                var line = "[\(entry.timestamp)] [\(entry.level)]"
                if !entry.processName.isEmpty { line += " \(entry.processName)" }
                if entry.pid > 0 { line += "(\(entry.pid))" }
                if !entry.subsystem.isEmpty { line += " [\(entry.subsystem)" }
                if !entry.category.isEmpty { line += ":\(entry.category)" }
                if !entry.subsystem.isEmpty { line += "]" }
                line += " \(entry.message)"
                lines.append(line)
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to stop log capture: \(error.localizedDescription)"
            ))
        }
    }
}
