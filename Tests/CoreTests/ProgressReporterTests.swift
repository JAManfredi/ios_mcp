//
//  ProgressReporterTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core

@Suite("ProgressReporter")
struct ProgressReporterTests {

    @Test("Sends notification when token is set")
    func sendsWhenTokenSet() async {
        let received = TokenCapture()
        let reporter = ProgressReporter { token, progress, total, message in
            await received.record(token: token, progress: progress, total: total, message: message)
        }

        await reporter.setToken(.string("test-token"))
        await reporter.report(message: "Compiling — 5s")
        await reporter.report(message: "Linking — 12s")

        let entries = await received.entries
        #expect(entries.count == 2)
        #expect(entries[0].token == .string("test-token"))
        #expect(entries[0].progress == 1)
        #expect(entries[0].message == "Compiling — 5s")
        #expect(entries[1].progress == 2)
        #expect(entries[1].message == "Linking — 12s")
    }

    @Test("No-ops when token is nil")
    func noOpWhenNilToken() async {
        let received = TokenCapture()
        let reporter = ProgressReporter { token, progress, total, message in
            await received.record(token: token, progress: progress, total: total, message: message)
        }

        await reporter.report(message: "Should not send")

        let entries = await received.entries
        #expect(entries.isEmpty)
    }

    @Test("Resets step count when token changes")
    func resetsStepCountOnTokenChange() async {
        let received = TokenCapture()
        let reporter = ProgressReporter { token, progress, total, message in
            await received.record(token: token, progress: progress, total: total, message: message)
        }

        await reporter.setToken(.string("first"))
        await reporter.report(message: "Step 1")
        await reporter.report(message: "Step 2")

        await reporter.setToken(.integer(42))
        await reporter.report(message: "New step 1")

        let entries = await received.entries
        #expect(entries.count == 3)
        #expect(entries[0].progress == 1)
        #expect(entries[1].progress == 2)
        #expect(entries[2].token == .integer(42))
        #expect(entries[2].progress == 1)
    }

    @Test("Clearing token stops reporting")
    func clearingTokenStopsReporting() async {
        let received = TokenCapture()
        let reporter = ProgressReporter { token, progress, total, message in
            await received.record(token: token, progress: progress, total: total, message: message)
        }

        await reporter.setToken(.string("active"))
        await reporter.report(message: "Before clear")
        await reporter.setToken(nil)
        await reporter.report(message: "After clear")

        let entries = await received.entries
        #expect(entries.count == 1)
        #expect(entries[0].message == "Before clear")
    }
}

// MARK: - Helpers

private actor TokenCapture {
    struct Entry {
        let token: ProgressToken
        let progress: Double
        let total: Double?
        let message: String?
    }

    private(set) var entries: [Entry] = []

    func record(
        token: ProgressToken,
        progress: Double,
        total: Double?,
        message: String?
    ) {
        entries.append(Entry(token: token, progress: progress, total: total, message: message))
    }
}
