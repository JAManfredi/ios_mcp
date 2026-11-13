//
//  WhereAmITool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerWhereAmITool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    navGraph: NavGraphStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "where_am_i",
        description: "Identify the current screen by capturing the accessibility tree and matching it against the loaded navigation graph's node fingerprints. Returns the matched node ID and confidence level, or a list of candidate nodes if no match is found. Requires a loaded nav graph.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .navigation,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        guard await navGraph.isLoaded() else {
            return .success(ToolResult(
                content: "No navigation graph is loaded. Use inspect_ui to see the current screen's accessibility tree directly.",
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

        var udid: String?
        if case .string(let u) = args["udid"] { udid = u }
        if udid == nil { udid = await session.get(.simulatorUDID) }

        guard let resolvedUDID = udid else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No simulator UDID provided, and no session default is set. Run list_simulators first."
            ))
        }

        if let error = await validator.validateSimulatorUDID(resolvedUDID) {
            return .error(error)
        }

        let snapshot: ScreenSnapshot
        switch await captureScreenSnapshot(udid: resolvedUDID, executor: executor) {
        case .success(let captured): snapshot = captured
        case .failure(let error): return .error(error)
        }
        let accessibilityIds = snapshot.accessibilityIdSet
        let staticTexts = snapshot.staticTexts

        let matches = await navGraph.fingerprintMatches(
            accessibilityIds: accessibilityIds,
            staticTexts: staticTexts,
            labelsByAccessibilityId: snapshot.labelsByAccessibilityId
        )
        let topMatches = matches.filter { $0.confidence == matches.first?.confidence }

        // Several nodes match equally well: the fingerprints don't tell these screens apart.
        if topMatches.count > 1 {
            var output = "Ambiguous: \(topMatches.count) nodes match the current screen with \(topMatches[0].confidence) confidence.\n"
            for match in topMatches {
                let name = await navGraph.getNode(match.nodeId)?.name ?? match.nodeId
                output += "  - \(match.nodeId) (\(name))\n"
            }
            output += "\nTheir fingerprints likely capture shared UI (tab bar, navigation bar). "
            output += "Re-tag them with tag_screen force=true and an accessibility_id unique to each screen, "
            output += "or pass 'from' to navigate_to explicitly."
            return .success(ToolResult(
                content: output,
                nextSteps: [
                    NextStep(tool: "tag_screen", description: "Re-tag an ambiguous node with a screen-specific accessibility ID"),
                    NextStep(tool: "inspect_ui", description: "Find an accessibility ID unique to this screen"),
                ]
            ))
        }

        if let match = topMatches.first {
            let node = await navGraph.getNode(match.nodeId)
            let nodeName = node?.name ?? match.nodeId

            var output = "Current screen: \(nodeName) (\(match.nodeId))\n"
            output += "Confidence: \(match.confidence)\n"

            if let node {
                if let template = node.deeplinkTemplate {
                    output += "Deeplink: \(template)\n"
                }
                if let subTabs = node.subTabs, !subTabs.isEmpty {
                    output += "Sub-tabs: \(subTabs.map(\.name).joined(separator: ", "))\n"
                }
            }

            // Show available outgoing edges
            let outgoing = await navGraph.edges(from: match.nodeId)
            if !outgoing.isEmpty {
                let targets = outgoing.compactMap(\.to)
                let unique = Array(Set(targets)).sorted()
                output += "Can navigate to: \(unique.joined(separator: ", "))\n"
            }

            return .success(ToolResult(
                content: output,
                nextSteps: [
                    NextStep(
                        tool: "navigate_to",
                        description: "Navigate to another screen",
                        context: ["from": match.nodeId]
                    ),
                    NextStep(
                        tool: "get_nav_graph",
                        description: "View details for this node",
                        context: ["node_id": match.nodeId]
                    ),
                ]
            ))
        }

        // No match — provide diagnostic info
        let allNodes = await navGraph.allNodes().sorted { $0.id < $1.id }
        let nodesWithFingerprints = allNodes.filter { $0.fingerprint != nil }
        let nodesWithout = allNodes.filter { $0.fingerprint == nil }

        var output = "Could not identify the current screen.\n\n"
        output += "Fingerprint data collected:\n"
        output += "  Accessibility IDs found: \(snapshot.accessibilityIds.count)\n"
        output += "  Static texts found: \(staticTexts.count)\n\n"

        if !snapshot.accessibilityIds.isEmpty {
            let sample = snapshot.accessibilityIds.prefix(10).joined(separator: ", ")
            output += "  Sample IDs: \(sample)\n"
        }

        if !staticTexts.isEmpty {
            let sample = staticTexts.prefix(5).joined(separator: ", ")
            output += "  Sample texts: \(sample)\n"
        }

        output += "\nGraph has \(nodesWithFingerprints.count) nodes with fingerprints, "
        output += "\(nodesWithout.count) without.\n"

        if !nodesWithout.isEmpty {
            let names = nodesWithout.prefix(10).map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
            output += "Nodes missing fingerprints: \(names)\n"
        }

        output += "\nTip: Add a fingerprint to the target node in the nav graph, "
        output += "or use get_nav_graph to browse nodes and provide the 'from' parameter to navigate_to manually."

        return .success(ToolResult(content: output))
    }
}
