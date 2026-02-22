//
//  StartLogCaptureTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStartLogCaptureTool(
    with registry: ToolRegistry,
    session: SessionStore,
    logCapture: any LogCapturing,
    concurrency: ConcurrencyPolicy
) async {
    let manifest = ToolManifest(
        name: "start_log_capture",
        description: "Start capturing logs from an iOS simulator. Returns a session ID for later retrieval with stop_log_capture. Falls back to session default for udid. Supports filtering by bundle_id, process_name, pid, subsystem, and category.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "Filter logs to this bundle identifier."
                ),
                "process_name": .init(
                    type: "string",
                    description: "Filter logs to this process name."
                ),
                "pid": .init(
                    type: "number",
                    description: "Filter logs to this process ID."
                ),
                "subsystem": .init(
                    type: "string",
                    description: "Filter logs to this subsystem."
                ),
                "category": .init(
                    type: "string",
                    description: "Filter logs to this category."
                ),
                "buffer_size": .init(
                    type: "number",
                    description: "Maximum number of log entries to retain (default 50000)."
                ),
            ]
        ),
        category: .logging
    )

    await registry.register(manifest: manifest) { args in
        do {
            let udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            } else {
                udid = await session.get(.simulatorUDID)
            }

            guard let udid else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No simulator UDID specified, and no session default is set. Run list_simulators first."
                ))
            }

            // Build NSPredicate-style filter string
            var predicateParts: [String] = []
            if case .string(let bundleID) = args["bundle_id"] {
                predicateParts.append("processImagePath CONTAINS '\(bundleID)'")
            }
            if case .string(let processName) = args["process_name"] {
                predicateParts.append("process == '\(processName)'")
            }
            if case .int(let pid) = args["pid"] {
                predicateParts.append("processID == \(pid)")
            }
            if case .string(let subsystem) = args["subsystem"] {
                predicateParts.append("subsystem == '\(subsystem)'")
            }
            if case .string(let category) = args["category"] {
                predicateParts.append("category == '\(category)'")
            }
            let predicate = predicateParts.isEmpty ? nil : predicateParts.joined(separator: " AND ")

            let bufferSize: Int
            if case .int(let size) = args["buffer_size"] {
                bufferSize = size
            } else {
                bufferSize = 50_000
            }

            let filterKey = predicate ?? "all"
            let lockKey = "log:\(udid):\(filterKey)"

            return await concurrency.withLock(key: lockKey, owner: "start_log_capture") {
                do {
                    let sessionID = try await logCapture.startCapture(
                        udid: udid,
                        predicate: predicate,
                        bufferSize: bufferSize
                    )

                    // Release the lock immediately — the capture runs independently
                    await concurrency.release(key: lockKey)

                    var lines = [
                        "Log capture started.",
                        "Session ID: \(sessionID)",
                        "Simulator: \(udid)",
                    ]
                    if let predicate { lines.append("Filter: \(predicate)") }
                    lines.append("Buffer size: \(bufferSize)")
                    lines.append("\nUse stop_log_capture with this session_id to retrieve logs.")

                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } catch let error as ToolError {
                    return .error(error)
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed to start log capture: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
