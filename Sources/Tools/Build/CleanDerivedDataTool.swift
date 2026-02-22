//
//  CleanDerivedDataTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerCleanDerivedDataTool(
    with registry: ToolRegistry,
    session: SessionStore
) async {
    let manifest = ToolManifest(
        name: "clean_derived_data",
        description: "Delete the DerivedData directory. Falls back to session default, then ~/Library/Developer/Xcode/DerivedData.",
        inputSchema: JSONSchema(
            properties: [
                "derived_data_path": .init(
                    type: "string",
                    description: "Path to DerivedData directory. Falls back to session default, then ~/Library/Developer/Xcode/DerivedData."
                ),
            ]
        ),
        category: .build,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        let path: String
        if case .string(let p) = args["derived_data_path"] {
            path = p
        } else if let sessionPath = await session.get(.derivedDataPath) {
            path = sessionPath
        } else {
            path = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return .error(ToolError(
                code: .invalidInput,
                message: "DerivedData path does not exist: \(path)"
            ))
        }

        do {
            try fm.removeItem(atPath: path)
            return .success(ToolResult(content: "Deleted DerivedData at \(path)."))
        } catch {
            return .error(ToolError(
                code: .commandFailed,
                message: "Failed to delete DerivedData: \(error.localizedDescription)"
            ))
        }
    }
}
