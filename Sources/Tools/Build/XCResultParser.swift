//
//  XCResultParser.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

// MARK: - Types

struct BuildDiagnostics: Sendable {
    let errors: [DiagnosticEntry]
    let warnings: [DiagnosticEntry]
}

struct DiagnosticEntry: Sendable {
    let message: String
    let file: String?
    let line: Int?
}

struct TestResults: Sendable {
    let totalTests: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let failedTests: [FailedTest]
}

struct FailedTest: Sendable {
    let name: String
    let message: String?
}

// MARK: - Parser Functions

/// Parses build diagnostics from xcresult JSON data.
/// Returns empty diagnostics on malformed or unexpected input.
func parseBuildDiagnostics(_ json: Data) -> BuildDiagnostics {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          let actions = root["actions"] as? [[String: Any]] else {
        return BuildDiagnostics(errors: [], warnings: [])
    }

    var errors: [DiagnosticEntry] = []
    var warnings: [DiagnosticEntry] = []

    for action in actions {
        guard let buildResult = action["buildResult"] as? [String: Any] else { continue }

        if let issues = buildResult["issues"] as? [String: Any] {
            if let errorSummaries = issues["errorSummaries"] as? [[String: Any]] {
                errors += errorSummaries.map { parseDiagnosticEntry($0) }
            }
            if let warningSummaries = issues["warningSummaries"] as? [[String: Any]] {
                warnings += warningSummaries.map { parseDiagnosticEntry($0) }
            }
        }
    }

    return BuildDiagnostics(errors: errors, warnings: warnings)
}

/// Parses test results from xcresult JSON data.
/// Returns zero counts on malformed or unexpected input.
func parseTestResults(_ json: Data) -> TestResults {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          let actions = root["actions"] as? [[String: Any]] else {
        return TestResults(totalTests: 0, passed: 0, failed: 0, skipped: 0, failedTests: [])
    }

    var total = 0
    var passed = 0
    var failed = 0
    var skipped = 0
    var failedTests: [FailedTest] = []

    for action in actions {
        guard let testResult = action["testResult"] as? [String: Any] else { continue }

        if let summary = testResult["summary"] as? [String: Any] {
            total += summary["totalCount"] as? Int ?? 0
            passed += summary["passedCount"] as? Int ?? 0
            failed += summary["failedCount"] as? Int ?? 0
            skipped += summary["skippedCount"] as? Int ?? 0
        }

        if let failures = testResult["failures"] as? [[String: Any]] {
            for failure in failures {
                let name = failure["testName"] as? String ?? "Unknown"
                let message = failure["message"] as? String
                failedTests.append(FailedTest(name: name, message: message))
            }
        }
    }

    return TestResults(
        totalTests: total,
        passed: passed,
        failed: failed,
        skipped: skipped,
        failedTests: failedTests
    )
}

/// Fetches and parses xcresult diagnostics via xcresulttool.
func fetchBuildDiagnostics(
    resultBundlePath: String,
    executor: any CommandExecuting
) async -> BuildDiagnostics {
    guard let data = await fetchXCResultJSON(path: resultBundlePath, executor: executor) else {
        return BuildDiagnostics(errors: [], warnings: [])
    }
    return parseBuildDiagnostics(data)
}

/// Fetches and parses xcresult test results via xcresulttool.
func fetchTestResults(
    resultBundlePath: String,
    executor: any CommandExecuting
) async -> TestResults {
    guard let data = await fetchXCResultJSON(path: resultBundlePath, executor: executor) else {
        return TestResults(totalTests: 0, passed: 0, failed: 0, skipped: 0, failedTests: [])
    }
    return parseTestResults(data)
}

// MARK: - Private

private func fetchXCResultJSON(
    path: String,
    executor: any CommandExecuting
) async -> Data? {
    guard let result = try? await executor.execute(
        executable: "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "--path", path, "--format", "json"],
        timeout: 30,
        environment: nil
    ), result.succeeded else {
        return nil
    }
    return result.stdout.data(using: .utf8)
}

private func parseDiagnosticEntry(_ dict: [String: Any]) -> DiagnosticEntry {
    let message = dict["message"] as? String ?? "Unknown error"

    var file: String?
    var line: Int?
    if let location = dict["documentLocationInCreatingWorkspace"] as? [String: Any] {
        file = location["url"] as? String
        if let lineStr = location["line"] as? String, let lineNum = Int(lineStr) {
            line = lineNum
        } else if let lineNum = location["line"] as? Int {
            line = lineNum
        }
    }

    return DiagnosticEntry(message: message, file: file, line: line)
}
