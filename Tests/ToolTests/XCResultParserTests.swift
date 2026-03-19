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
