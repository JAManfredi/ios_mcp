//
//  SaveNavGraphTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerSaveNavGraphTool(
    with registry: ToolRegistry,
    navGraph: NavGraphStore
) async {
    let manifest = ToolManifest(
        name: "save_nav_graph",
        description: "Save the current in-memory navigation graph to a JSON file. Useful after tagging screens with tag_screen to persist fingerprints. By default saves to the original load path. Provide a custom path to write a separate copy (recommended to avoid overwriting the source graph).",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Absolute path to write the graph. If omitted, overwrites the file it was loaded from."
                ),
            ]
        ),
        category: .navigation
    )

    await registry.register(manifest: manifest) { args in
        guard await navGraph.isLoaded() else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No navigation graph loaded. Nothing to save."
            ))
        }

        var savePath: String?
        if case .string(let p) = args["path"] { savePath = p }

        do {
            try await navGraph.save(to: savePath)

            let originalPath = await navGraph.getGraphPath()
            let destination = savePath ?? originalPath ?? "(unknown)"
            return .success(ToolResult(
                content: "Navigation graph saved to: \(destination)"
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to save navigation graph: \(error.localizedDescription)"
            ))
        }
    }
}
