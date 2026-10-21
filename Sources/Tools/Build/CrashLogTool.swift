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
                if filename.contains(processName) || filename.contains(bundleID) { return true }
                // .ips names use the executable name, which often differs from the
                // last bundle ID component; the JSON header carries the real ID.
                return path.hasSuffix(".ips") && ipsHeaderBundleID(atPath: path) == bundleID
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
                output.append(contentsOf: summarizeIPS(content).map { "  \($0)" })
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

// MARK: - .ips Parsing

/// Summarizes a modern `.ips` crash report (iOS 15+ / macOS 12+).
///
/// The format is two JSON documents: a one-line header (`app_name`,
/// `bundleID`, `timestamp`, `bug_type`), then a multi-line body holding
/// `exception`, `termination`, `faultingThread`, `threads[].frames` and
/// `usedImages`. There is no plain-text "Thread N Crashed:" section, so the
/// backtrace has to be rebuilt from the body.
func summarizeIPS(_ content: String, maxFrames: Int = 15) -> [String] {
    let documents = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    let header = documents.first.flatMap { jsonObject(String($0)) }
    let body = documents.count > 1 ? jsonObject(String(documents[1])) : nil

    guard header != nil || body != nil else {
        return ["(.ips JSON not parseable)"]
    }

    var lines: [String] = []
    let procName = body?["procName"] as? String ?? header?["app_name"] as? String ?? header?["name"] as? String ?? "?"
    lines.append("Process: \(procName)")
    if let bundle = header?["bundleID"] as? String { lines.append("Bundle: \(bundle)") }
    if let timestamp = header?["timestamp"] as? String ?? body?["captureTime"] as? String {
        lines.append("Timestamp: \(timestamp)")
    }

    if let exception = body?["exception"] as? [String: Any] {
        let type = exception["type"] as? String ?? "?"
        let signal = exception["signal"] as? String ?? "?"
        var line = "Exception: \(type) (\(signal))"
        if let subtype = exception["subtype"] as? String { line += " — \(subtype)" }
        lines.append(line)
    }
    if let termination = body?["termination"] as? [String: Any],
       let indicator = termination["indicator"] as? String {
        lines.append("Termination: \(indicator)")
    }
    if let asi = body?["asi"] as? [String: [String]] {
        for message in asi.values.flatMap({ $0 }).prefix(3) {
            lines.append("Message: \(message)")
        }
    }

    // Older reports put a plain-text log after the JSON header.
    if body == nil {
        let frames = extractCrashedThread(from: content)
        if !frames.isEmpty {
            lines.append("Crashed thread backtrace:")
            lines.append(contentsOf: frames.prefix(maxFrames).map { "  \($0)" })
        }
        return lines
    }

    guard let threads = body?["threads"] as? [[String: Any]], !threads.isEmpty else {
        return lines
    }
    let faulting = body?["faultingThread"] as? Int
        ?? threads.firstIndex { $0["triggered"] as? Bool == true }
        ?? 0
    guard threads.indices.contains(faulting) else { return lines }

    let images = (body?["usedImages"] as? [[String: Any]]) ?? []
    let frames = threads[faulting]["frames"] as? [[String: Any]] ?? []
    if let queue = threads[faulting]["queue"] as? String {
        lines.append("Crashed thread \(faulting) (\(queue)) backtrace:")
    } else {
        lines.append("Crashed thread \(faulting) backtrace:")
    }

    for (index, frame) in frames.prefix(maxFrames).enumerated() {
        let imageIndex = frame["imageIndex"] as? Int
        let image = imageIndex.flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil } ?? "???"
        var line = "  \(index) \(image)"
        if let symbol = frame["symbol"] as? String {
            line += " \(symbol)"
            if let offset = frame["symbolLocation"] as? Int { line += " + \(offset)" }
        } else if let offset = frame["imageOffset"] as? Int {
            line += " + \(offset)"
        }
        if let file = frame["sourceFile"] as? String {
            line += " (\(file)"
            if let lineNumber = frame["sourceLine"] as? Int { line += ":\(lineNumber)" }
            line += ")"
        }
        lines.append(line)
    }
    if frames.count > maxFrames {
        lines.append("  ... (\(frames.count - maxFrames) more frames)")
    }
    return lines
}

/// The `bundleID` from an .ips file's first line, without reading the body.
private func ipsHeaderBundleID(atPath path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    let chunk = (try? handle.read(upToCount: 4096)) ?? Data()
    guard let text = String(data: chunk, encoding: .utf8),
          let firstLine = text.split(separator: "\n", maxSplits: 1).first else { return nil }
    return jsonObject(String(firstLine))?["bundleID"] as? String
}

private func jsonObject(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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
