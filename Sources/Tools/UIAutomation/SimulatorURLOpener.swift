//
//  SimulatorURLOpener.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Opens URLs on simulators without getting stuck on iOS's "Open in “App”?" prompt.
///
/// The first time `simctl openurl` opens a custom scheme on a simulator, iOS
/// may ask for confirmation and record the answer in the simulator's
/// `com.apple.launchservices.schemeapproval` defaults. AXe can't tap that
/// system alert, and while it is up each later link queues another one. So
/// before the first open of a scheme on a simulator, the opener records the
/// approval for the installed app that declares the scheme, opens the URL,
/// and checks the screen once for the prompt. After a clean check, later
/// opens of that scheme on that simulator skip both steps.
actor SimulatorURLOpener {
    private var verifiedSchemes: Set<String> = []
    private let promptCheckDelay: Duration

    init(promptCheckDelay: Duration = .milliseconds(500)) {
        self.promptCheckDelay = promptCheckDelay
    }

    /// Open `url` on the simulator. On success, returns notes worth showing the
    /// caller (an approval recorded, or a prompt check that couldn't run).
    func open(
        _ url: String,
        udid: String,
        executor: any CommandExecuting
    ) async -> Result<[String], ToolError> {
        guard let scheme = URL(string: url)?.scheme?.lowercased(),
              scheme != "http", scheme != "https" else {
            return await openURL(url, udid: udid, executor: executor).map { [] }
        }

        let key = "\(udid)|\(scheme)"
        if verifiedSchemes.contains(key) {
            return await openURL(url, udid: udid, executor: executor).map { [] }
        }

        var notes: [String] = []
        if let note = await approveScheme(scheme, udid: udid, executor: executor) {
            notes.append(note)
        }

        if case .failure(let error) = await openURL(url, udid: udid, executor: executor) {
            return .failure(error)
        }

        try? await Task.sleep(for: promptCheckDelay)
        switch await captureScreenSnapshot(udid: udid, executor: executor) {
        case .success(let snapshot):
            if let prompt = snapshot.staticTexts.first(where: Self.isOpenConfirmation) {
                return .failure(ToolError(
                    code: .commandFailed,
                    message: "iOS is asking \"\(prompt)\" and the link has not opened.",
                    details: "AXe can't tap this system alert. Accept it in the Simulator window (click Open, or press Return with the window focused); iOS remembers the choice for this scheme. Until then, each retry queues another prompt."
                        + (notes.isEmpty ? "" : " " + notes.joined(separator: " "))
                ))
            }
            verifiedSchemes.insert(key)
        case .failure(let error):
            notes.append("Could not check for an \"Open in\" confirmation prompt: \(error.message)")
        }
        return .success(notes)
    }

    /// The text of iOS's confirmation alert, e.g. `Open in “MyApp”?` (English only).
    static func isOpenConfirmation(_ text: String) -> Bool {
        text.hasPrefix("Open in \u{201C}") && text.hasSuffix("?")
    }

    private func openURL(
        _ url: String,
        udid: String,
        executor: any CommandExecuting
    ) async -> Result<Void, ToolError> {
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "openurl", udid, url],
                timeout: 60,
                environment: nil
            )
            guard result.succeeded else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(ToolError(
                    code: .commandFailed,
                    message: stderr.isEmpty ? "simctl openurl failed" : "simctl openurl failed: \(stderr)",
                    details: result.stderr
                ))
            }
            return .success(())
        } catch let error as ToolError {
            return .failure(error)
        } catch {
            return .failure(ToolError(code: .internalError, message: "Failed to open URL: \(error.localizedDescription)"))
        }
    }

    /// Record that `simctl openurl` may open `scheme` in the one installed app
    /// that declares it. Returns a note for the caller, or nil when there is
    /// nothing worth reporting.
    private func approveScheme(
        _ scheme: String,
        udid: String,
        executor: any CommandExecuting
    ) async -> String? {
        let handlers = await installedHandlers(of: scheme, udid: udid, executor: executor)
        guard handlers.count == 1, let bundleId = handlers.first else {
            if handlers.isEmpty { return nil }
            return "Several installed apps declare '\(scheme)' (\(handlers.sorted().joined(separator: ", "))), so no approval was recorded."
        }

        let result = try? await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: [
                "simctl", "spawn", udid, "defaults", "write", "com.apple.launchservices.schemeapproval",
                "com.apple.CoreSimulator.CoreSimulatorBridge-->\(scheme)", "-string", bundleId,
            ],
            timeout: 30,
            environment: nil
        )
        guard result?.succeeded == true else {
            return "Could not pre-approve '\(scheme)' links for \(bundleId): \(result?.stderr ?? "defaults write did not run")."
        }
        return nil
    }

    /// Bundle IDs of user-installed apps whose Info.plist declares `scheme`.
    private func installedHandlers(
        of scheme: String,
        udid: String,
        executor: any CommandExecuting
    ) async -> [String] {
        guard let result = try? await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "listapps", udid],
            timeout: 30,
            environment: nil
        ), result.succeeded,
            let data = result.stdout.data(using: .utf8),
            let apps = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]]
        else { return [] }

        return apps.compactMap { bundleId, app in
            guard app["ApplicationType"] as? String == "User",
                  let path = app["Path"] as? String,
                  let infoData = FileManager.default.contents(atPath: "\(path)/Info.plist"),
                  let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                  let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] else { return nil }
            let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            return schemes.contains { $0.lowercased() == scheme } ? bundleId : nil
        }
    }
}
