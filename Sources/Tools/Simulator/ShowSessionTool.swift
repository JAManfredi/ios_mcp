//
//  ShowSessionTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerShowSessionTool(
    with registry: ToolRegistry,
    session: SessionStore
) async {
    let manifest = ToolManifest(
        name: "show_session",
        description: "Display all current session defaults (simulator UDID, workspace, scheme, bundle ID, etc.).",
        inputSchema: JSONSchema(),
        category: .simulator,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { _ in
        let defaults = await session.allDefaults()

        guard !defaults.isEmpty else {
            return .success(ToolResult(
                content: "No session defaults are set."
            ))
        }

        var lines = ["Session defaults:"]
        for key in SessionStore.Key.allCases {
            if let value = defaults[key] {
                lines.append("  \(key.rawValue) = \(value)")
            }
        }

        return .success(ToolResult(content: lines.joined(separator: "\n")))
    }
}
