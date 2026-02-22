//
//  AxeTargetArgsTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

@Suite("AxeTargetArgs")
struct AxeTargetArgsTests {

    @Test("Prefers accessibility_id over label and coordinates")
    func prefersAccessibilityID() {
        let result = resolveAxeTarget(from: [
            "accessibility_id": .string("loginButton"),
            "accessibility_label": .string("Log In"),
            "x": .int(100),
            "y": .int(200),
        ])

        if case .success(let args) = result {
            #expect(args == ["--identifier", "loginButton"])
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("Falls back to label when no accessibility_id")
    func fallsBackToLabel() {
        let result = resolveAxeTarget(from: [
            "accessibility_label": .string("Submit"),
            "x": .int(50),
            "y": .int(75),
        ])

        if case .success(let args) = result {
            #expect(args == ["--label", "Submit"])
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("Falls back to coordinates when no accessibility target")
    func coordinateFallback() {
        let result = resolveAxeTarget(from: [
            "x": .int(150),
            "y": .int(300),
        ])

        if case .success(let args) = result {
            #expect(args == ["--x", "150", "--y", "300"])
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("Returns invalidInput when no target provided")
    func noTarget() {
        let result = resolveAxeTarget(from: [:])

        if case .failure(let error) = result {
            #expect(error.code == .invalidInput)
            #expect(error.message.contains("No target"))
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("Handles .int coordinate values")
    func intCoordinates() {
        let result = resolveAxeTarget(from: [
            "x": .int(42),
            "y": .int(84),
        ])

        if case .success(let args) = result {
            #expect(args == ["--x", "42", "--y", "84"])
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("Handles .double coordinate values")
    func doubleCoordinates() {
        let result = resolveAxeTarget(from: [
            "x": .double(42.5),
            "y": .double(84.9),
        ])

        if case .success(let args) = result {
            #expect(args == ["--x", "42", "--y", "84"])
        } else {
            Issue.record("Expected success")
        }
    }
}
