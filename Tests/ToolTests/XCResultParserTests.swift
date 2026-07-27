//
//  XCResultParserTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("XCResultParser")
struct XCResultParserTests {

    // MARK: - Build Diagnostics

    @Test("Parses errors and warnings from build-results JSON")
    func parseDiagnosticsHappyPath() {
        let json = """
        {
          "destination": {
            "deviceId": "abc",
            "deviceName": "iPhone 16",
            "architecture": "arm64",
            "modelName": "iPhone",
            "osVersion": "18.0"
          },
          "startTime": 1700000000.0,
          "endTime": 1700000060.0,
          "status": "failed",
          "errorCount": 2,
          "warningCount": 1,
          "analyzerWarningCount": 0,
          "errors": [
            {
              "issueType": "Swift Compiler Error",
              "message": "Use of undeclared type 'Foo'",
              "sourceURL": "file:///src/Bar.swift#CharacterRangeLen=0&EndingColumnNumber=5&EndingLineNumber=42&StartingColumnNumber=5&StartingLineNumber=42"
            },
            {
              "issueType": "Swift Compiler Error",
              "message": "Cannot convert value of type 'Int' to 'String'"
            }
          ],
          "warnings": [
            {
              "issueType": "Swift Compiler Warning",
              "message": "Result of call to 'doThing()' is unused"
            }
          ],
          "analyzerWarnings": []
        }
        """.data(using: .utf8)!

        let diagnostics = parseBuildDiagnostics(json)

        #expect(diagnostics.errors.count == 2)
        #expect(diagnostics.warnings.count == 1)
        #expect(diagnostics.errors[0].message == "Use of undeclared type 'Foo'")
        #expect(diagnostics.errors[0].issueType == "Swift Compiler Error")
        #expect(diagnostics.errors[0].sourceURL?.contains("Bar.swift") == true)
        #expect(diagnostics.errors[1].message == "Cannot convert value of type 'Int' to 'String'")
        #expect(diagnostics.errors[1].sourceURL == nil)
        #expect(diagnostics.warnings[0].message == "Result of call to 'doThing()' is unused")
    }

    @Test("Returns empty diagnostics for empty arrays")
    func parseDiagnosticsEmptyArrays() {
        let json = """
        {
          "errors": [],
          "warnings": [],
          "analyzerWarnings": []
        }
        """.data(using: .utf8)!

        let diagnostics = parseBuildDiagnostics(json)
        #expect(diagnostics.errors.isEmpty)
        #expect(diagnostics.warnings.isEmpty)
    }

    @Test("Returns empty diagnostics for malformed JSON")
    func parseDiagnosticsMalformed() {
        let json = "not valid json".data(using: .utf8)!
        let diagnostics = parseBuildDiagnostics(json)
        #expect(diagnostics.errors.isEmpty)
        #expect(diagnostics.warnings.isEmpty)
    }

    @Test("Returns empty diagnostics for missing keys")
    func parseDiagnosticsMissingKeys() {
        let json = """
        { "other": "data" }
        """.data(using: .utf8)!
        let diagnostics = parseBuildDiagnostics(json)
        #expect(diagnostics.errors.isEmpty)
        #expect(diagnostics.warnings.isEmpty)
    }

    // MARK: - Test Results

    @Test("Parses test results from test-results summary JSON")
    func parseTestResultsHappyPath() {
        let json = """
        {
          "title": "Test Scheme Action",
          "environmentDescription": "Test Plan on iPhone 16, iOS 18.0",
          "topInsights": [],
          "result": "Failed",
          "totalTestCount": 5,
          "passedTests": 3,
          "failedTests": 1,
          "skippedTests": 1,
          "expectedFailures": 0,
          "statistics": [],
          "devicesAndConfigurations": {},
          "testFailures": [
            {
              "testName": "testSomethingBroken()",
              "targetName": "MyTests",
              "failureText": "XCTAssertEqual failed: (1) is not equal to (2)",
              "testIdentifier": 0,
              "testIdentifierString": "MyTests/testSomethingBroken()"
            }
          ]
        }
        """.data(using: .utf8)!

        let results = parseTestResults(json)

        #expect(results.totalTests == 5)
        #expect(results.passed == 3)
        #expect(results.failed == 1)
        #expect(results.skipped == 1)
        #expect(results.failedTests.count == 1)
        #expect(results.failedTests[0].name == "testSomethingBroken()")
        #expect(results.failedTests[0].message == "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    @Test("Parses passing test results")
    func parseTestResultsAllPassing() {
        let json = """
        {
          "title": "Test Scheme Action",
          "environmentDescription": "Test Plan on iPhone 16, iOS 18.0",
          "topInsights": [],
          "result": "Passed",
          "totalTestCount": 14,
          "passedTests": 14,
          "failedTests": 0,
          "skippedTests": 0,
          "expectedFailures": 0,
          "statistics": [],
          "devicesAndConfigurations": {},
          "testFailures": []
        }
        """.data(using: .utf8)!

        let results = parseTestResults(json)

        #expect(results.totalTests == 14)
        #expect(results.passed == 14)
        #expect(results.failed == 0)
        #expect(results.skipped == 0)
        #expect(results.failedTests.isEmpty)
    }

    @Test("Returns zeros for malformed JSON")
    func parseTestResultsMalformed() {
        let json = "not valid json".data(using: .utf8)!
        let results = parseTestResults(json)
        #expect(results.totalTests == 0)
        #expect(results.failedTests.isEmpty)
    }

    @Test("Returns zeros for missing keys")
    func parseTestResultsMissingKeys() {
        let json = """
        { "other": "data" }
        """.data(using: .utf8)!
        let results = parseTestResults(json)
        #expect(results.totalTests == 0)
        #expect(results.passed == 0)
        #expect(results.failedTests.isEmpty)
    }
}

@Suite("DiagnosticEntry location")
struct DiagnosticEntryLocationTests {

    @Test("Extracts file, line and column from an xcresult sourceURL")
    func parsesFileLineColumn() {
        let entry = DiagnosticEntry(
            message: "ambiguous use of operator '*'",
            issueType: "Swift Compiler Error",
            sourceURL: "file:///Users/x/Analysis/SwingMetrics.swift"
                + "#EndingColumnNumber=94&EndingLineNumber=152"
                + "&StartingColumnNumber=94&StartingLineNumber=152"
        )
        #expect(entry.location == "SwingMetrics.swift:152:94")
    }

    @Test("Falls back to the file name when the URL carries no line numbers")
    func parsesFileOnly() {
        let entry = DiagnosticEntry(
            message: "no such module",
            issueType: nil,
            sourceURL: "file:///Users/x/Sources/Thing.swift"
        )
        #expect(entry.location == "Thing.swift")
    }

    @Test("Reports no location when the diagnostic has no source URL")
    func noSourceURL() {
        let entry = DiagnosticEntry(message: "linker error", issueType: nil, sourceURL: nil)
        #expect(entry.location == nil)
    }
}

@Suite("Axe health")
struct AxeHealthTests {

    @Test("Reads a real binary's architectures from its header")
    func detectsArchitecture() {
        let arches = machOArchitectures(at: "/bin/ls")
        #expect(arches != nil)
        #expect(arches?.contains(hostArchitecture()) == true)
    }

    /// A universal binary must list its actual slices. Reporting a placeholder
    /// failed the host-architecture check and declared a runnable binary
    /// incompatible.
    @Test("Universal binaries report every slice, not a placeholder")
    func expandsUniversalSlices() throws {
        let candidates = ["/usr/bin/xcrun", "/bin/ls", "/usr/bin/true"]
        let fat = candidates.compactMap { machOArchitectures(at: $0) }.first { $0.count > 1 }
        try #require(fat != nil, "expected at least one universal system binary")
        #expect(fat?.contains("universal") == false)
        #expect(fat?.contains(hostArchitecture()) == true)
    }

    @Test("A shell wrapper resolves to the executable it runs")
    func followsWrapper() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wrapper = dir.appendingPathComponent("axe")
        let script = ["#!/bin/bash", "exec \"/bin/ls\" \"$@\"", ""].joined(separator: "\n")
        try script.write(to: wrapper, atomically: true, encoding: .utf8)

        #expect(resolveWrappedExecutable(at: wrapper.path) == "/bin/ls")
    }

    @Test("A plain binary path resolves to itself")
    func leavesBinaryAlone() {
        #expect(resolveWrappedExecutable(at: "/bin/ls") == "/bin/ls")
    }

    /// The launcher's own complaint has to be enough on its own — the wrapper
    /// may be unfollowable and the header unparseable.
    @Test("A bad CPU type failure is diagnosed even without a readable header")
    func diagnosesFromFailureText() {
        let detail = axeFailureDetail(
            binaryPath: "/nonexistent/axe",
            failure: "Failed to launch: Bad CPU type in executable"
        )
        #expect(detail.contains("brew upgrade"))
    }

    @Test("A runnable binary failing for other reasons is not blamed on architecture")
    func doesNotBlameArchitecture() {
        let detail = axeFailureDetail(binaryPath: "/bin/ls", failure: "some other error")
        #expect(detail.contains("--version failed"))
        #expect(detail.contains("brew upgrade") == false)
    }

    @Test("Flags an axe older than the supported minimum")
    func warnsOnOldVersion() {
        #expect(axeVersionWarning(reported: "axe 1.4.0") != nil)
        #expect(axeVersionWarning(reported: "1.8.0") == nil)
        #expect(axeVersionWarning(reported: "1.9.2") == nil)
    }

    @Test("Compares versions componentwise, not lexically")
    func comparesVersions() {
        #expect(isVersion("1.4.0", olderThan: "1.8.0"))
        #expect(isVersion("1.10.0", olderThan: "1.8.0") == false)
        #expect(isVersion("1.8", olderThan: "1.8.0") == false)
    }

    @Test("Extracts a version from surrounding text")
    func extractsVersion() {
        #expect(firstSemanticVersion(in: "AXe version 1.8.0 (build 42)") == "1.8.0")
        #expect(firstSemanticVersion(in: "no version here") == nil)
    }
}
