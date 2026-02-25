//
//  ClearSessionTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerClearSessionTool(
    with registry: ToolRegistry,
    session: SessionStore
) async {
    let manifest = ToolManifest(
        name: "clear_session",
        description: "Clear session defaults. Omit 'keys' to clear all. Pass comma-separated key names to clear specific defaults (e.g. 'simulator_udid,bundle_id').",
        inputSchema: JSONSchema(
            properties: [
                "keys": .init(
                    type: "string",
                    description: "Comma-separated key names to clear (e.g. 'simulator_udid,bundle_id'). Omit to clear all."
                ),
            ]
        ),
        category: .simulator,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        if case .string(let keysString) = args["keys"] {
            let keyNames = keysString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var cleared: [String] = []
            var invalid: [String] = []

            for name in keyNames {
                if let key = SessionStore.Key(rawValue: name) {
                    await session.remove(key)
                    cleared.append(name)
                } else {
                    invalid.append(name)
                }
            }

            if !invalid.isEmpty {
                let validKeys = SessionStore.Key.allCases.map(\.rawValue).joined(separator: ", ")
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Unknown session key(s): \(invalid.joined(separator: ", ")). Valid keys: \(validKeys)"
                ))
            }

            return .success(ToolResult(
                content: "Cleared session defaults: \(cleared.joined(separator: ", "))"
            ))
        }

        await session.reset()
        return .success(ToolResult(
            content: "All session defaults cleared."
        ))
    }
}
