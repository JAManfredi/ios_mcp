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

        var output: [String] = ["XCResult Inspection: \(path)", ""]

        // MARK: Diagnostics & Timeline (from build-results)
        if requestedSections.contains("diagnostics") || requestedSections.contains("timeline") {
            let buildJSON = await fetchBuildResults(path: path, executor: executor)

            if requestedSections.contains("diagnostics") {
                output.append("## Diagnostics")
                if let build = buildJSON {
                    let errors = build["errors"] as? [[String: Any]] ?? []
                    let warnings = build["warnings"] as? [[String: Any]] ?? []
                    let errorCount = build["errorCount"] as? Int ?? errors.count
                    let warningCount = build["warningCount"] as? Int ?? warnings.count

                    if errors.isEmpty && warnings.isEmpty {
                        output.append("No diagnostics found (errors: \(errorCount), warnings: \(warningCount)).")
                    } else {
                        if !errors.isEmpty {
                            output.append("Errors (\(errorCount)):")
                            for entry in errors.prefix(50) {
                                let message = entry["message"] as? String ?? "Unknown error"
                                let issueType = entry["issueType"] as? String
                                var line = "  - \(message)"
                                if let t = issueType { line += " [\(t)]" }
                                output.append(line)
                            }
                        }
                        if !warnings.isEmpty {
                            output.append("Warnings (\(warningCount)):")
                            for entry in warnings.prefix(20) {
                                let message = entry["message"] as? String ?? "Unknown warning"
                                output.append("  - \(message)")
                            }
                            if warnings.count > 20 {
                                output.append("  ... and \(warnings.count - 20) more")
                            }
                        }
                    }
                } else {
                    output.append("Build results not available.")
                }
                output.append("")
            }

            if requestedSections.contains("timeline") {
                output.append("## Build Timeline")
                if let build = buildJSON {
                    let startTime = build["startTime"] as? Double
                    let endTime = build["endTime"] as? Double
                    let status = build["status"] as? String ?? "unknown"
                    output.append("Status: \(status)")
                    if let start = startTime, let end = endTime {
                        let duration = end - start
                        output.append("Duration: \(String(format: "%.1fs", duration))")
                    }
                    if let dest = build["destination"] as? [String: Any] {
                        let deviceName = dest["deviceName"] as? String ?? "?"
                        let osVersion = dest["osVersion"] as? String ?? "?"
                        output.append("Destination: \(deviceName) (iOS \(osVersion))")
                    }
                } else {
                    output.append("No timeline data available.")
                }
                output.append("")
            }
        }

        // MARK: Tests
        if requestedSections.contains("tests") {
            output.append("## Test Results")

            if let testSummary = await fetchTestSummary(path: path, executor: executor) {
                let total = testSummary["totalTestCount"] as? Int ?? 0
                let passed = testSummary["passedTests"] as? Int ?? 0
                let failed = testSummary["failedTests"] as? Int ?? 0
                let skipped = testSummary["skippedTests"] as? Int ?? 0
                let result = testSummary["result"] as? String ?? "unknown"

                output.append("Result: \(result)")
                output.append("Total: \(total) | Passed: \(passed) | Failed: \(failed) | Skipped: \(skipped)")

                if let failures = testSummary["testFailures"] as? [[String: Any]], !failures.isEmpty {
                    output.append("Failures:")
                    for failure in failures.prefix(20) {
                        let testName = failure["testName"] as? String ?? "?"
                        let message = failure["message"] as? String ?? ""
                        output.append("  - \(testName): \(message)")
                    }
                }

                if let title = testSummary["title"] as? String {
                    output.append("Title: \(title)")
                }
            } else {
                output.append("Test results not available.")
            }
            output.append("")
        }

        // MARK: Coverage
        if requestedSections.contains("coverage") {
            output.append("## Code Coverage")

            if let covResult = try? await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["xcresulttool", "get", "object", "--legacy", "--path", path, "--format", "json", "--type", "codeCoverage"],
                timeout: 30,
                environment: nil
            ), covResult.succeeded,
               let covData = covResult.stdout.data(using: .utf8),
               let covJSON = try? JSONSerialization.jsonObject(with: covData) as? [String: Any],
               let targets = covJSON["targets"] as? [[String: Any]] {
                for target in targets {
                    let name = target["name"] as? String ?? "Unknown"
                    let lineCoverage = target["lineCoverage"] as? Double ?? 0.0
                    output.append("  \(name): \(String(format: "%.1f%%", lineCoverage * 100))")

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

        return .success(ToolResult(content: output.joined(separator: "\n")))
    }
}

// MARK: - xcresulttool Helpers

/// Fetches build-results JSON from xcresulttool.
private func fetchBuildResults(
    path: String,
    executor: any CommandExecuting
) async -> [String: Any]? {
    guard let result = try? await executor.execute(
        executable: "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "build-results", "--path", path, "--format", "json"],
        timeout: 30,
        environment: nil
    ), result.succeeded,
          let data = result.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return json
}

/// Fetches test-results summary JSON from xcresulttool.
private func fetchTestSummary(
    path: String,
    executor: any CommandExecuting
) async -> [String: Any]? {
    guard let result = try? await executor.execute(
        executable: "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "test-results", "summary", "--path", path],
        timeout: 30,
        environment: nil
    ), result.succeeded,
          let data = result.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return json
}
