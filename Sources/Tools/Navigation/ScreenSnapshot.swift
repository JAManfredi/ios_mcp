//
//  ScreenSnapshot.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Accessibility identifiers and visible static text from one `axe describe-ui` capture.
///
/// Navigation tools fingerprint screens from this data. It is always read from
/// AXe directly, independent of which backend `inspect_ui` uses, so the keys
/// parsed here stay stable.
struct ScreenSnapshot: Equatable {
    /// Non-empty `AXUniqueId` values in tree order, without duplicates.
    let accessibilityIds: [String]
    /// Text of static text elements in tree order, duplicates kept.
    let staticTexts: [String]

    var accessibilityIdSet: Set<String> { Set(accessibilityIds) }

    /// Static texts without duplicates, in first-seen order.
    var uniqueStaticTexts: [String] {
        var seen = Set<String>()
        return staticTexts.filter { seen.insert($0).inserted }
    }

    /// Parse `axe describe-ui` JSON output. Returns nil if it isn't a JSON array of elements.
    ///
    /// AXe reports the element role under `role` (e.g. `AXStaticText`) and the
    /// visible text of static text under `AXLabel`; `AXValue` is a fallback.
    static func parse(_ output: String) -> ScreenSnapshot? {
        guard let data = output.data(using: .utf8),
              let roots = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        var ids: [String] = []
        var seenIds = Set<String>()
        var texts: [String] = []

        func visit(_ element: [String: Any]) {
            if let uid = element["AXUniqueId"] as? String, !uid.isEmpty, seenIds.insert(uid).inserted {
                ids.append(uid)
            }
            if isStaticText(element), let text = nonEmpty(element["AXLabel"]) ?? nonEmpty(element["AXValue"]) {
                texts.append(text)
            }
            for child in element["children"] as? [[String: Any]] ?? [] {
                visit(child)
            }
        }

        roots.forEach(visit)
        return ScreenSnapshot(accessibilityIds: ids, staticTexts: texts)
    }

    private static func isStaticText(_ element: [String: Any]) -> Bool {
        (element["role"] as? String) == "AXStaticText" || (element["type"] as? String) == "StaticText"
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

/// Capture the current screen with `axe describe-ui` and parse it.
func captureScreenSnapshot(
    udid: String,
    executor: any CommandExecuting
) async -> Result<ScreenSnapshot, ToolError> {
    let axePath: String
    switch resolveAxePath() {
    case .success(let path): axePath = path
    case .failure(let error): return .failure(error)
    }

    let output: String
    do {
        let result = try await executor.execute(
            executable: axePath,
            arguments: ["describe-ui", "--udid", udid],
            timeout: 120,
            environment: nil
        )
        guard result.succeeded else { return .failure(axeCommandError("axe describe-ui failed", stderr: result.stderr)) }
        output = result.stdout
    } catch let error as ToolError {
        return .failure(error)
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to capture UI snapshot: \(error.localizedDescription)"
        ))
    }

    guard let snapshot = ScreenSnapshot.parse(output) else {
        return .failure(ToolError(
            code: .commandFailed,
            message: "Failed to parse accessibility tree output as JSON."
        ))
    }
    return .success(snapshot)
}
