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
    let issueType: String?
    let sourceURL: String?
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

/// Parses build diagnostics from `xcresulttool get build-results` JSON.
func parseBuildDiagnostics(_ json: Data) -> BuildDiagnostics {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
        return BuildDiagnostics(errors: [], warnings: [])
    }

    let errors = (root["errors"] as? [[String: Any]] ?? []).map { parseDiagnosticEntry($0) }
    let warnings = (root["warnings"] as? [[String: Any]] ?? []).map { parseDiagnosticEntry($0) }

    return BuildDiagnostics(errors: errors, warnings: warnings)
}

/// Parses test results from `xcresulttool get test-results summary` JSON.
func parseTestResults(_ json: Data) -> TestResults {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
        return TestResults(totalTests: 0, passed: 0, failed: 0, skipped: 0, failedTests: [])
    }

    let total = root["totalTestCount"] as? Int ?? 0
    let passed = root["passedTests"] as? Int ?? 0
    let failed = root["failedTests"] as? Int ?? 0
    let skipped = root["skippedTests"] as? Int ?? 0

    var failedTestEntries: [FailedTest] = []
    if let failures = root["testFailures"] as? [[String: Any]] {
        for failure in failures {
            let name = failure["testName"] as? String ?? "Unknown"
            let message = failure["failureText"] as? String
            failedTestEntries.append(FailedTest(name: name, message: message))
        }
    }

    return TestResults(
        totalTests: total,
        passed: passed,
        failed: failed,
        skipped: skipped,
        failedTests: failedTestEntries
    )
}

/// Fetches and parses build diagnostics via `xcresulttool get build-results`.
func fetchBuildDiagnostics(
    resultBundlePath: String,
    executor: any CommandExecuting
) async -> BuildDiagnostics {
    guard let data = await fetchBuildResultsJSON(path: resultBundlePath, executor: executor) else {
        return BuildDiagnostics(errors: [], warnings: [])
    }
    return parseBuildDiagnostics(data)
}

/// Fetches and parses test results via `xcresulttool get test-results summary`.
func fetchTestResults(
    resultBundlePath: String,
    executor: any CommandExecuting
) async -> TestResults {
    guard let data = await fetchTestSummaryJSON(path: resultBundlePath, executor: executor) else {
        return TestResults(totalTests: 0, passed: 0, failed: 0, skipped: 0, failedTests: [])
    }
    return parseTestResults(data)
}

// MARK: - Private

private func fetchBuildResultsJSON(
    path: String,
    executor: any CommandExecuting
) async -> Data? {
    guard let result = try? await executor.execute(
        executable: "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "build-results", "--path", path],
        timeout: 30,
        environment: nil
    ), result.succeeded else {
        return nil
    }
    return result.stdout.data(using: .utf8)
}

private func fetchTestSummaryJSON(
    path: String,
    executor: any CommandExecuting
) async -> Data? {
    guard let result = try? await executor.execute(
        executable: "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "test-results", "summary", "--path", path],
        timeout: 30,
        environment: nil
    ), result.succeeded else {
        return nil
    }
    return result.stdout.data(using: .utf8)
}

private func parseDiagnosticEntry(_ dict: [String: Any]) -> DiagnosticEntry {
    let message = dict["message"] as? String ?? "Unknown error"
    let issueType = dict["issueType"] as? String
    let sourceURL = dict["sourceURL"] as? String

    return DiagnosticEntry(message: message, issueType: issueType, sourceURL: sourceURL)
}
