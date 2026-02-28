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

        // Capture the accessibility tree via inspect_ui
        let resolvedAxe: String
        switch resolveAxePath() {
        case .success(let path): resolvedAxe = path
        case .failure(let error): return .error(error)
        }

        let treeOutput: String
        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: ["describe-ui", "--udid", resolvedUDID],
                timeout: 120,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "axe describe-ui failed",
                    details: result.stderr
                ))
            }

            treeOutput = result.stdout
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to capture UI snapshot: \(error.localizedDescription)"
            ))
        }

        // Parse accessibility IDs and static texts from the tree
        guard let data = treeOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .error(ToolError(
                code: .commandFailed,
                message: "Failed to parse accessibility tree output as JSON."
            ))
        }

        var accessibilityIds = Set<String>()
        var staticTexts: [String] = []
        collectFingerprint(from: json, ids: &accessibilityIds, texts: &staticTexts)

        // Match against graph fingerprints
        if let match = await navGraph.matchFingerprint(
            accessibilityIds: accessibilityIds,
            staticTexts: staticTexts
        ) {
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
        let allNodes = await navGraph.allNodes()
        let nodesWithFingerprints = allNodes.filter { $0.fingerprint != nil }
        let nodesWithout = allNodes.filter { $0.fingerprint == nil }

        var output = "Could not identify the current screen.\n\n"
        output += "Fingerprint data collected:\n"
        output += "  Accessibility IDs found: \(accessibilityIds.count)\n"
        output += "  Static texts found: \(staticTexts.count)\n\n"

        if !accessibilityIds.isEmpty {
            let sample = Array(accessibilityIds.prefix(10)).joined(separator: ", ")
            output += "  Sample IDs: \(sample)\n"
        }

        if !staticTexts.isEmpty {
            let sample = Array(staticTexts.prefix(5)).joined(separator: ", ")
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

// MARK: - Helpers

private func collectFingerprint(
    from nodes: [[String: Any]],
    ids: inout Set<String>,
    texts: inout [String]
) {
    for node in nodes {
        if let uid = node["AXUniqueId"] as? String, !uid.isEmpty {
            ids.insert(uid)
        }
        if let role = node["AXRole"] as? String, role == "AXStaticText",
           let value = node["AXValue"] as? String, !value.isEmpty {
            texts.append(value)
        }
        if let children = node["children"] as? [[String: Any]] {
            collectFingerprint(from: children, ids: &ids, texts: &texts)
        }
    }
}
