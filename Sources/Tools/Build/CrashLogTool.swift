//
//  CrashLogTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerCrashLogTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "list_crash_logs",
        description: "Find and parse crash reports from an iOS simulator. Extracts exception type, crashed thread, and symbolicated backtrace from .ips and .crash files.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "Filter to a specific app's crashes. Falls back to session default."
                ),
                "limit": .init(
                    type: "number",
                    description: "Maximum number of crash logs to return (default: 5)."
                ),
            ]
        ),
        category: .build,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        let bundleID: String?
        if case .string(let bid) = args["bundle_id"] {
            bundleID = bid
        } else {
            bundleID = await session.get(.bundleID)
        }

        let limit: Int
        if case .int(let l) = args["limit"] {
            limit = max(1, l)
        } else {
            limit = 5
        }

        // Crash reports directory
        let crashDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/DiagnosticReports")
        let fm = FileManager.default

        guard fm.fileExists(atPath: crashDir) else {
            return .success(ToolResult(content: "No crash log directory found at \(crashDir)."))
        }

        guard let files = try? fm.contentsOfDirectory(atPath: crashDir) else {
            return .success(ToolResult(content: "Unable to read crash log directory."))
        }

        // Filter to .ips and .crash files
        var crashFiles = files.filter { $0.hasSuffix(".ips") || $0.hasSuffix(".crash") }
            .map { (crashDir as NSString).appendingPathComponent($0) }

        // Filter by bundle_id if provided (check filename contains the bundle ID or process name)
        if let bundleID {
            let processName = bundleID.components(separatedBy: ".").last ?? bundleID
            crashFiles = crashFiles.filter { path in
                let filename = (path as NSString).lastPathComponent
                return filename.contains(processName) || filename.contains(bundleID)
            }
        }

        // Sort by modification date (newest first)
        crashFiles.sort { path1, path2 in
            let date1 = (try? fm.attributesOfItem(atPath: path1)[.modificationDate] as? Date) ?? .distantPast
            let date2 = (try? fm.attributesOfItem(atPath: path2)[.modificationDate] as? Date) ?? .distantPast
            return date1 > date2
        }

        let selected = Array(crashFiles.prefix(limit))

        if selected.isEmpty {
            var msg = "No crash logs found"
            if let bundleID { msg += " for '\(bundleID)'" }
            msg += " in \(crashDir)."
            return .success(ToolResult(content: msg))
        }

        var output: [String] = ["Crash logs (\(selected.count) of \(crashFiles.count)):", ""]

        for path in selected {
            let filename = (path as NSString).lastPathComponent
            output.append("--- \(filename) ---")

            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                output.append("  (unable to read file)")
                output.append("")
                continue
            }

            if path.hasSuffix(".ips") {
                // .ips format: first line is JSON header, rest is plain text crash log
                let lines = content.components(separatedBy: .newlines)
                if let firstLine = lines.first,
                   let headerData = firstLine.data(using: .utf8),
                   let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                    let procName = header["procName"] as? String ?? "?"
                    let timestamp = header["timestamp"] as? String ?? "?"
                    let exception = header["exception"] as? [String: Any]
                    let exceptionType = exception?["type"] as? String ?? "?"
                    let signal = exception?["signal"] as? String ?? header["termination"] as? String ?? "?"

                    output.append("  Process: \(procName)")
                    output.append("  Timestamp: \(timestamp)")
                    output.append("  Exception: \(exceptionType) (\(signal))")
                } else {
                    output.append("  (JSON header not parseable)")
                }

                // Extract crashed thread backtrace from plain text portion
                let crashedThreadLines = extractCrashedThread(from: content)
                if !crashedThreadLines.isEmpty {
                    output.append("  Crashed thread backtrace:")
                    for line in crashedThreadLines.prefix(15) {
                        output.append("    \(line)")
                    }
                    if crashedThreadLines.count > 15 {
                        output.append("    ... (\(crashedThreadLines.count - 15) more frames)")
                    }
                }
            } else {
                // .crash format: plain text throughout
                let lines = content.components(separatedBy: .newlines)

                // Extract key fields from the header
                for line in lines.prefix(20) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Process:") || trimmed.hasPrefix("Date/Time:") ||
                       trimmed.hasPrefix("Exception Type:") || trimmed.hasPrefix("Exception Codes:") ||
                       trimmed.hasPrefix("Termination Reason:") {
                        output.append("  \(trimmed)")
                    }
                }

                let crashedThreadLines = extractCrashedThread(from: content)
                if !crashedThreadLines.isEmpty {
                    output.append("  Crashed thread backtrace:")
                    for line in crashedThreadLines.prefix(15) {
                        output.append("    \(line)")
                    }
                    if crashedThreadLines.count > 15 {
                        output.append("    ... (\(crashedThreadLines.count - 15) more frames)")
                    }
                }
            }

            output.append("")
        }

        return .success(ToolResult(content: output.joined(separator: "\n")))
    }
}

/// Extracts the crashed thread's stack frames from a crash log.
/// Looks for "Thread N Crashed:" and captures lines until the next blank line.
private func extractCrashedThread(from content: String) -> [String] {
    let lines = content.components(separatedBy: .newlines)
    var inCrashedThread = false
    var frames: [String] = []

    for line in lines {
        if line.contains("Crashed:") && line.contains("Thread") {
            inCrashedThread = true
            continue
        }
        if inCrashedThread {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            frames.append(trimmed)
        }
    }

    return frames
}
