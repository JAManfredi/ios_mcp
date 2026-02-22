//
//  LogCaptureManagerTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("LogCaptureManager")
struct LogCaptureManagerTests {

    // MARK: - Log Line Parser

    @Test("Parses valid JSON log line")
    func parseValidLogLine() {
        let line = """
        {"timestamp":"2024-01-15 10:30:00","processImagePath":"MyApp","processID":12345,"subsystem":"com.example","category":"network","messageType":"Default","eventMessage":"Request completed"}
        """

        let entry = parseLogLine(line)
        #expect(entry != nil)
        #expect(entry?.timestamp == "2024-01-15 10:30:00")
        #expect(entry?.processName == "MyApp")
        #expect(entry?.pid == 12345)
        #expect(entry?.subsystem == "com.example")
        #expect(entry?.category == "network")
        #expect(entry?.level == "Default")
        #expect(entry?.message == "Request completed")
    }

    @Test("Returns nil for invalid JSON")
    func parseInvalidJSON() {
        let entry = parseLogLine("not json at all")
        #expect(entry == nil)
    }

    @Test("Returns nil for empty string")
    func parseEmptyString() {
        let entry = parseLogLine("")
        #expect(entry == nil)
    }

    @Test("Handles alternate key names")
    func parseAlternateKeys() {
        let line = """
        {"timestamp":"2024-01-15","process":"SomeProcess","pid":999,"subsystem":"","category":"","level":"Error","message":"Something failed"}
        """

        let entry = parseLogLine(line)
        #expect(entry != nil)
        #expect(entry?.processName == "SomeProcess")
        #expect(entry?.pid == 999)
        #expect(entry?.level == "Error")
        #expect(entry?.message == "Something failed")
    }

    @Test("Handles missing optional fields gracefully")
    func parseMissingFields() {
        let line = """
        {"eventMessage":"Just a message"}
        """

        let entry = parseLogLine(line)
        #expect(entry != nil)
        #expect(entry?.message == "Just a message")
        #expect(entry?.timestamp == "")
        #expect(entry?.processName == "")
        #expect(entry?.pid == 0)
        #expect(entry?.subsystem == "")
    }
}
