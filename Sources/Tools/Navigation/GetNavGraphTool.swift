//
//  GetNavGraphTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerGetNavGraphTool(
    with registry: ToolRegistry,
    navGraph: NavGraphStore
) async {
    let manifest = ToolManifest(
        name: "get_nav_graph",
        description: "Returns a summary of the loaded navigation graph including all nodes, their deeplink templates, and available edges. Use this to understand the app's navigation structure before using navigate_to.",
        inputSchema: JSONSchema(
            properties: [
                "include_edges": .init(
                    type: "boolean",
                    description: "Include full edge details in the response. Defaults to false (node summary only)."
                ),
                "node_id": .init(
                    type: "string",
                    description: "If provided, returns details for a single node and its edges only."
                ),
            ]
        ),
        category: .navigation,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        guard await navGraph.isLoaded() else {
            return .success(ToolResult(
                content: "No navigation graph is loaded. Use inspect_ui to explore the current screen directly, or load_nav_graph to load a graph if one is available.",
                nextSteps: [
                    NextStep(
                        tool: "inspect_ui",
                        description: "Capture the accessibility tree to understand the current screen"
                    ),
                    NextStep(
                        tool: "load_nav_graph",
                        description: "Load a navigation graph if one is available"
                    ),
                ]
            ))
        }

        var includeEdges = false
        if case .bool(let b) = args["include_edges"] {
            includeEdges = b
        }

        // Single node detail mode
        if case .string(let nodeId) = args["node_id"] {
            guard let node = await navGraph.getNode(nodeId) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Node '\(nodeId)' not found in graph."
                ))
            }

            let edgesTo = await navGraph.edges(to: nodeId)

            var output = "Node: \(node.name) (\(node.id))\n"
            output += "  Tab root: \(node.isTabRoot)\n"
            if let tabs = node.supportedTabs, !tabs.isEmpty {
                output += "  Supported tabs: \(tabs.joined(separator: ", "))\n"
            }
            if let template = node.deeplinkTemplate {
                output += "  Deeplink: \(template)\n"
            }
            if let subTabs = node.subTabs, !subTabs.isEmpty {
                output += "  Sub-tabs:\n"
                for sub in subTabs {
                    output += "    - \(sub.name): \(sub.deeplinkTemplate)\n"
                }
            }
            output += "  Edges leading here: \(edgesTo.count)\n"
            for edge in edgesTo {
                let actionSummary = edge.actions.map(\.type.rawValue).joined(separator: ", ")
                output += "    - from: \(edge.from), actions: [\(actionSummary)]\n"
            }

            return .success(ToolResult(content: output))
        }

        // Full graph summary mode
        guard let graph = await navGraph.getGraph() else {
            return .error(ToolError(
                code: .internalError,
                message: "Graph is loaded but could not be read."
            ))
        }

        var output = "Navigation Graph v\(graph.version) (\(graph.app))\n"
        output += "═══════════════════════════════════\n\n"

        // Nodes
        let sortedNodes = graph.nodes.values.sorted { a, b in
            if a.isTabRoot != b.isTabRoot { return a.isTabRoot }
            return a.id < b.id
        }

        output += "NODES (\(sortedNodes.count)):\n"
        for node in sortedNodes {
            let prefix = node.isTabRoot ? "📍" : "  "
            let template = node.deeplinkTemplate ?? "(no direct deeplink)"
            output += "\(prefix) \(node.id) — \(node.name)\n"
            output += "    \(template)\n"
        }

        if includeEdges {
            output += "\nEDGES (\(graph.edges.count)):\n"
            for edge in graph.edges {
                let target = edge.to ?? "(action only)"
                let actionTypes = edge.actions.map(\.type.rawValue).joined(separator: " → ")
                output += "  \(edge.from) → \(target) [\(actionTypes)]\n"
            }
        }

        // Commands
        if let commands = graph.commands, !commands.isEmpty {
            output += "\nCOMMANDS (\(commands.count)):\n"
            for cmd in commands {
                output += "  \(cmd.id): \(cmd.deeplinkTemplate) — \(cmd.description)\n"
            }
        }

        return .success(ToolResult(content: output))
    }
}
