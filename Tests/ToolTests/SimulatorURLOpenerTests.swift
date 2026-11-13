//
//  SimulatorURLOpenerTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

private let axeInstalled: Bool = {
    if case .success = resolveAxePath() { return true }
    return false
}()

private let emptyScreen = #"[{"role": "AXApplication", "children": []}]"#
private let promptScreen = #"[{"role": "AXApplication", "children": [{"role": "AXStaticText", "AXLabel": "Open in “Example”?", "children": []}]}]"#

/// Writes an app bundle whose Info.plist declares `schemes`, and returns its path.
private func makeApp(schemes: [String]) throws -> String {
    let app = FileManager.default.temporaryDirectory.appendingPathComponent("opener-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": schemes]]]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: app.appendingPathComponent("Info.plist"))
    return app.path
}

/// `simctl listapps` output (an old-style plist) for user apps at the given paths.
private func listApps(_ apps: [String: String]) -> String {
    let entries = apps.map { bundleId, path in
        "\"\(bundleId)\" = { ApplicationType = User; Path = \"\(path)\"; };"
    }
    return "{ " + entries.joined(separator: " ") + " }"
}

private func executor(
    listapps: String,
    screen: String,
    calls: AllCallCapture
) -> MockCommandExecutor {
    MockCommandExecutor { _, args in
        await calls.capture(args)
        if args.contains("listapps") { return CommandResult(stdout: listapps, stderr: "", exitCode: 0) }
        if args.contains("describe-ui") { return CommandResult(stdout: screen, stderr: "", exitCode: 0) }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

@Suite("SimulatorURLOpener", .enabled(if: axeInstalled))
struct SimulatorURLOpenerTests {

    @Test("Pre-approves the scheme for its handler, checks once, then opens directly")
    func approvesThenSkips() async throws {
        let calls = AllCallCapture()
        let apps = listApps(["com.example.app": try makeApp(schemes: ["ExampleApp"])])
        let opener = SimulatorURLOpener(promptCheckDelay: .zero)
        let mock = executor(listapps: apps, screen: emptyScreen, calls: calls)

        let first = await opener.open("exampleapp://home", udid: "AAAA-1111", executor: mock)
        guard case .success(let notes) = first else { Issue.record("Expected success: \(first)"); return }
        #expect(notes.isEmpty)

        let recorded = await calls.allArgs
        let write = recorded.first { $0.contains("write") }
        #expect(write == [
            "simctl", "spawn", "AAAA-1111", "defaults", "write", "com.apple.launchservices.schemeapproval",
            "com.apple.CoreSimulator.CoreSimulatorBridge-->exampleapp", "-string", "com.example.app",
        ])
        let writeIndex = try #require(recorded.firstIndex { $0.contains("write") })
        let openIndex = try #require(recorded.firstIndex { $0.contains("openurl") })
        #expect(writeIndex < openIndex)

        _ = await opener.open("exampleapp://live", udid: "AAAA-1111", executor: mock)
        let second = await calls.allArgs.dropFirst(recorded.count)
        #expect(Array(second) == [["simctl", "openurl", "AAAA-1111", "exampleapp://live"]])
    }

    @Test("Reports iOS's confirmation prompt instead of claiming the link opened")
    func reportsPrompt() async throws {
        let calls = AllCallCapture()
        let opener = SimulatorURLOpener(promptCheckDelay: .zero)
        let mock = executor(listapps: listApps([:]), screen: promptScreen, calls: calls)

        let result = await opener.open("exampleapp://home", udid: "AAAA-1111", executor: mock)
        guard case .failure(let error) = result else { Issue.record("Expected failure"); return }
        #expect(error.code == .commandFailed)
        #expect(error.message.contains("Open in “Example”?"))
        #expect(error.details?.contains("Simulator window") == true)
    }

    @Test("Doesn't guess when several apps declare the scheme")
    func ambiguousHandlers() async throws {
        let calls = AllCallCapture()
        let apps = listApps([
            "com.example.one": try makeApp(schemes: ["shared"]),
            "com.example.two": try makeApp(schemes: ["shared"]),
        ])
        let opener = SimulatorURLOpener(promptCheckDelay: .zero)

        let result = await opener.open("shared://x", udid: "AAAA-1111", executor: executor(listapps: apps, screen: emptyScreen, calls: calls))
        guard case .success(let notes) = result else { Issue.record("Expected success"); return }
        #expect(notes.first?.contains("com.example.one, com.example.two") == true)
        #expect(await calls.allArgs.contains { $0.contains("write") } == false)
    }

    @Test("Web links open without approval or a prompt check")
    func webLinksSkipChecks() async throws {
        let calls = AllCallCapture()
        let opener = SimulatorURLOpener(promptCheckDelay: .zero)

        _ = await opener.open("https://example.com/a", udid: "AAAA-1111", executor: executor(listapps: "", screen: promptScreen, calls: calls))
        #expect(await calls.allArgs == [["simctl", "openurl", "AAAA-1111", "https://example.com/a"]])
    }

    @Test("Recognizes the confirmation text")
    func confirmationText() {
        #expect(SimulatorURLOpener.isOpenConfirmation("Open in “MyApp”?"))
        #expect(!SimulatorURLOpener.isOpenConfirmation("Open in Safari"))
    }
}
