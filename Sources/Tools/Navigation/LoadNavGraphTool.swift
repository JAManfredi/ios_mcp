//
//  LoadNavGraphTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Common locations to search for a nav graph file, relative to a base directory.
private let searchPaths = [
    "nav_graph.json",
    "nav-graph/nav_graph.json",
    "navigation/nav_graph.json",
]

func registerLoadNavGraphTool(
    with registry: ToolRegistry,
    navGraph: NavGraphStore
) async {
    let manifest = ToolManifest(
        name: "load_nav_graph",
        description: "Load a navigation graph from a JSON file. The graph describes the app's screens (nodes), transitions (edges), and the actions needed to traverse them. Once loaded, use navigate_to to move between screens and where_am_i to identify the current screen. If no path is provided, searches common locations in the working directory. If no graph is found, navigation tools are unavailable — use inspect_ui, tap, swipe, and deep_link directly instead.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Absolute path to the nav_graph.json file. If omitted, searches the working directory for common locations (nav_graph.json, nav-graph/nav_graph.json)."
                ),
            ]
        ),
        category: .navigation
    )

    await registry.register(manifest: manifest) { args in
        var resolvedPath: String?

        if case .string(let path) = args["path"] {
            resolvedPath = path
        } else {
            // Auto-discover from working directory
            let cwd = FileManager.default.currentDirectoryPath
            for candidate in searchPaths {
                let full = (cwd as NSString).appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: full) {
                    resolvedPath = full
                    break
                }
            }
        }

        guard let path = resolvedPath else {
            return .success(ToolResult(
                content: "No navigation graph found. Searched the working directory for: \(searchPaths.joined(separator: ", ")).\n\nThis is normal — navigation graphs are optional. Continue using inspect_ui, tap, swipe, and deep_link for direct UI interaction.",
                nextSteps: [
                    NextStep(
                        tool: "inspect_ui",
                        description: "Capture the accessibility tree to understand the current screen"
                    ),
                ]
            ))
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return .success(ToolResult(
                content: "File not found: \(path)\n\nNavigation graph not available. Continue using inspect_ui, tap, swipe, and deep_link for direct UI interaction.",
                nextSteps: [
                    NextStep(
                        tool: "inspect_ui",
                        description: "Capture the accessibility tree to understand the current screen"
                    ),
                ]
            ))
        }

        do {
            try await navGraph.load(from: path)

            guard let graph = await navGraph.getGraph() else {
                return .error(ToolError(
                    code: .internalError,
                    message: "Graph loaded but could not be read back."
                ))
            }

            let nodeCount = graph.nodes.count
            let edgeCount = graph.edges.count
            let tabRoots = graph.nodes.values.filter { $0.isTabRoot }.map(\.name)
            let commandCount = graph.commands?.count ?? 0

            var summary = "Navigation graph loaded (v\(graph.version), app: \(graph.app)).\n"
            summary += "  \(nodeCount) nodes, \(edgeCount) edges, \(commandCount) commands\n"
            summary += "  Tab roots: \(tabRoots.joined(separator: ", "))"

            // Surface reference files so the agent knows where to look up parameter values
            let graphDir = (path as NSString).deletingLastPathComponent
            if let refs = graph.references, !refs.isEmpty {
                summary += "\n\n  Reference files (for parameter lookup):"
                for ref in refs {
                    let absPath = (graphDir as NSString).appendingPathComponent(ref.file)
                    summary += "\n    \(absPath)"
                    summary += "\n      \(ref.description)"
                }
            }

            return .success(ToolResult(
                content: summary,
                nextSteps: [
                    NextStep(
                        tool: "get_nav_graph",
                        description: "View the full graph structure"
                    ),
                    NextStep(
                        tool: "where_am_i",
                        description: "Identify the current screen in the graph"
                    ),
                ]
            ))
        } catch {
            return .error(ToolError(
                code: .invalidInput,
                message: "Failed to parse nav graph: \(error.localizedDescription)",
                details: "Ensure the file conforms to the NavGraph JSON schema."
            ))
        }
    }
}
