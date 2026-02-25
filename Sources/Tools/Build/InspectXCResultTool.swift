//
//  InspectXCResultTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerInspectXCResultTool(
    with registry: ToolRegistry,
    executor: any CommandExecuting,
    artifacts: ArtifactStore
) async {
    let manifest = ToolManifest(
        name: "inspect_xcresult",
        description: "Deep inspection of an xcresult bundle. Extracts diagnostics, test results, code coverage, attachments, and build timeline. The xcresult path is returned by build_sim, test_sim, and build_run_sim.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the .xcresult bundle (required)."
                ),
                "sections": .init(
                    type: "string",
                    description: "Comma-separated list of sections to extract: diagnostics, tests, coverage, attachments, timeline. Default: all."
                ),
            ],
            required: ["path"]
        ),
        category: .build,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let path) = args["path"] else {
            return .error(ToolError(code: .invalidInput, message: "path is required."))
        }

        let requestedSections: Set<String>
        if case .string(let sections) = args["sections"] {
            requestedSections = Set(sections.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            requestedSections = ["diagnostics", "tests", "coverage", "attachments", "timeline"]
        }

        // Fetch the xcresult JSON
        guard let result = try? await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["xcresulttool", "get", "--path", path, "--format", "json"],
            timeout: 30,
            environment: nil
        ), result.succeeded, let data = result.stdout.data(using: .utf8) else {
            return .error(ToolError(
                code: .commandFailed,
                message: "Failed to read xcresult bundle at '\(path)'. Verify the path exists and contains a valid .xcresult."
            ))
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = root["actions"] as? [[String: Any]] else {
            return .error(ToolError(
                code: .commandFailed,
                message: "Unable to parse xcresult JSON. The format may not be supported."
            ))
        }

        var output: [String] = ["XCResult Inspection: \(path)", ""]

        // MARK: Diagnostics
        if requestedSections.contains("diagnostics") {
            output.append("## Diagnostics")
            let diag = parseBuildDiagnostics(data)
            if diag.errors.isEmpty && diag.warnings.isEmpty {
                output.append("No diagnostics found.")
            } else {
                if !diag.errors.isEmpty {
                    output.append("Errors (\(diag.errors.count)):")
                    for entry in diag.errors {
                        var line = "  - \(entry.message)"
                        if let file = entry.file {
                            line += " (\(file)"
                            if let lineNum = entry.line { line += ":\(lineNum)" }
                            line += ")"
                        }
                        output.append(line)
                    }
                }
                if !diag.warnings.isEmpty {
                    output.append("Warnings (\(diag.warnings.count)):")
                    for entry in diag.warnings {
                        var line = "  - \(entry.message)"
                        if let file = entry.file {
                            line += " (\(file)"
                            if let lineNum = entry.line { line += ":\(lineNum)" }
                            line += ")"
                        }
                        output.append(line)
                    }
                }
            }
            output.append("")
        }

        // MARK: Tests
        if requestedSections.contains("tests") {
            output.append("## Test Results")
            let tests = parseTestResults(data)
            output.append("Total: \(tests.totalTests) | Passed: \(tests.passed) | Failed: \(tests.failed) | Skipped: \(tests.skipped)")
            if !tests.failedTests.isEmpty {
                output.append("Failed tests:")
                for test in tests.failedTests {
                    var line = "  - \(test.name)"
                    if let msg = test.message { line += ": \(msg)" }
                    output.append(line)
                }
            }

            // Extract per-test durations if available
            for action in actions {
                if let testResult = action["testResult"] as? [String: Any],
                   let testNodes = testResult["testNodes"] as? [[String: Any]] {
                    let durations = extractTestDurations(testNodes)
                    if !durations.isEmpty {
                        output.append("Test durations:")
                        for (name, duration) in durations.sorted(by: { $0.1 > $1.1 }).prefix(20) {
                            output.append("  \(name): \(String(format: "%.2fs", duration))")
                        }
                    }
                }
            }
            output.append("")
        }

        // MARK: Coverage
        if requestedSections.contains("coverage") {
            output.append("## Code Coverage")

            // Try fetching coverage data via xcresulttool
            if let covResult = try? await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["xcresulttool", "get", "--path", path, "--format", "json", "--type", "codeCoverage"],
                timeout: 30,
                environment: nil
            ), covResult.succeeded,
               let covData = covResult.stdout.data(using: .utf8),
               let covJSON = try? JSONSerialization.jsonObject(with: covData) as? [String: Any] {
                if let targets = covJSON["targets"] as? [[String: Any]] {
                    for target in targets {
                        let name = target["name"] as? String ?? "Unknown"
                        let lineCoverage = target["lineCoverage"] as? Double ?? 0.0
                        output.append("  \(name): \(String(format: "%.1f%%", lineCoverage * 100))")

                        // Per-file coverage (top 10 lowest)
                        if let files = target["files"] as? [[String: Any]] {
                            let sorted = files.sorted { ($0["lineCoverage"] as? Double ?? 0) < ($1["lineCoverage"] as? Double ?? 0) }
                            for file in sorted.prefix(10) {
                                let fileName = file["name"] as? String ?? "?"
                                let fileCov = file["lineCoverage"] as? Double ?? 0.0
                                output.append("    \(fileName): \(String(format: "%.1f%%", fileCov * 100))")
                            }
                        }
                    }
                } else {
                    output.append("No coverage data found.")
                }
            } else {
                output.append("Code coverage not available (tests may not have been run with coverage enabled).")
            }
            output.append("")
        }

        // MARK: Attachments
        if requestedSections.contains("attachments") {
            output.append("## Attachments")

            let tempDir = NSTemporaryDirectory() + "ios-mcp-xcresult-attachments-\(UUID().uuidString)"

            if let exportResult = try? await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["xcresulttool", "export", "--path", path, "--output-path", tempDir, "--type", "file"],
                timeout: 60,
                environment: nil
            ), exportResult.succeeded {
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(atPath: tempDir) {
                    let imageFiles = files.filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") }
                    output.append("Exported \(files.count) files (\(imageFiles.count) images)")
                    for file in imageFiles.prefix(10) {
                        let filePath = (tempDir as NSString).appendingPathComponent(file)
                        if let data = fm.contents(atPath: filePath) {
                            _ = try? await artifacts.store(data: data, filename: file, mimeType: "image/png")
                        }
                        output.append("  - \(file)")
                    }
                } else {
                    output.append("No attachments exported.")
                }
            } else {
                output.append("Attachment export not available or no attachments found.")
            }
            output.append("")
        }

        // MARK: Timeline
        if requestedSections.contains("timeline") {
            output.append("## Build Timeline")

            var hasTimeline = false
            for action in actions {
                if let buildResult = action["buildResult"] as? [String: Any] {
                    if let metrics = buildResult["metrics"] as? [String: Any] {
                        if let wallClock = metrics["totalWallClockTime"] as? Double {
                            output.append("Total wall clock time: \(String(format: "%.1fs", wallClock))")
                        }
                        if let cpuTime = metrics["totalCPUTime"] as? Double {
                            output.append("Total CPU time: \(String(format: "%.1fs", cpuTime))")
                        }
                        hasTimeline = true
                    }
                }

                // Per-target timing from build steps
                if let buildResult = action["buildResult"] as? [String: Any],
                   let steps = buildResult["buildSteps"] as? [[String: Any]] {
                    let targetTimes = steps.compactMap { step -> (String, Double)? in
                        guard let title = step["title"] as? String,
                              let duration = step["duration"] as? Double else { return nil }
                        return (title, duration)
                    }.sorted(by: { $0.1 > $1.1 })

                    if !targetTimes.isEmpty {
                        output.append("Per-target build duration (top 10):")
                        for (target, duration) in targetTimes.prefix(10) {
                            output.append("  \(target): \(String(format: "%.1fs", duration))")
                        }
                        hasTimeline = true
                    }
                }
            }

            if !hasTimeline {
                output.append("No timeline data available.")
            }
            output.append("")
        }

        return .success(ToolResult(content: output.joined(separator: "\n")))
    }
}

/// Recursively extract test durations from test node trees.
private func extractTestDurations(_ nodes: [[String: Any]]) -> [(String, Double)] {
    var result: [(String, Double)] = []
    for node in nodes {
        let name = node["name"] as? String ?? "?"
        if let duration = node["duration"] as? Double, duration > 0 {
            result.append((name, duration))
        }
        if let children = node["children"] as? [[String: Any]] {
            result += extractTestDurations(children)
        }
    }
    return result
}
