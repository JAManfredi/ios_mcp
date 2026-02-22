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

    @Test("Parses errors and warnings from xcresult JSON")
    func parseDiagnosticsHappyPath() {
        let json = """
        {
          "actions": [
            {
              "buildResult": {
                "issues": {
                  "errorSummaries": [
                    {
                      "message": "Use of undeclared type 'Foo'",
                      "documentLocationInCreatingWorkspace": {
                        "url": "file:///src/Bar.swift",
                        "line": 42
                      }
                    },
                    {
                      "message": "Cannot convert value of type 'Int' to 'String'"
                    }
                  ],
                  "warningSummaries": [
                    {
                      "message": "Result of call to 'doThing()' is unused"
                    }
                  ]
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let diagnostics = parseBuildDiagnostics(json)

        #expect(diagnostics.errors.count == 2)
        #expect(diagnostics.warnings.count == 1)
        #expect(diagnostics.errors[0].message == "Use of undeclared type 'Foo'")
        #expect(diagnostics.errors[0].file == "file:///src/Bar.swift")
        #expect(diagnostics.errors[0].line == 42)
        #expect(diagnostics.errors[1].message == "Cannot convert value of type 'Int' to 'String'")
        #expect(diagnostics.errors[1].file == nil)
        #expect(diagnostics.warnings[0].message == "Result of call to 'doThing()' is unused")
    }

    @Test("Returns empty diagnostics for empty actions")
    func parseDiagnosticsEmptyActions() {
        let json = """
        { "actions": [] }
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

    @Test("Returns empty diagnostics for missing actions key")
    func parseDiagnosticsMissingActions() {
        let json = """
        { "other": "data" }
        """.data(using: .utf8)!
        let diagnostics = parseBuildDiagnostics(json)
        #expect(diagnostics.errors.isEmpty)
        #expect(diagnostics.warnings.isEmpty)
    }

    // MARK: - Test Results

    @Test("Parses test results with pass, fail, and skip")
    func parseTestResultsHappyPath() {
        let json = """
        {
          "actions": [
            {
              "testResult": {
                "summary": {
                  "totalCount": 5,
                  "passedCount": 3,
                  "failedCount": 1,
                  "skippedCount": 1
                },
                "failures": [
                  {
                    "testName": "MyTests/testSomethingBroken",
                    "message": "XCTAssertEqual failed: (1) is not equal to (2)"
                  }
                ]
              }
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
        #expect(results.failedTests[0].name == "MyTests/testSomethingBroken")
        #expect(results.failedTests[0].message == "XCTAssertEqual failed: (1) is not equal to (2)")
    }

    @Test("Returns zeros for empty actions")
    func parseTestResultsEmptyActions() {
        let json = """
        { "actions": [] }
        """.data(using: .utf8)!

        let results = parseTestResults(json)
        #expect(results.totalTests == 0)
        #expect(results.passed == 0)
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
}
