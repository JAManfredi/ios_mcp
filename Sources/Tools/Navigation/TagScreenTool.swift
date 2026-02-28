//
//  TagScreenTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerTagScreenTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    navGraph: NavGraphStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "tag_screen",
        description: "Capture the current screen's accessibility fingerprint and associate it with a node in the loaded navigation graph. Navigate to a screen first, then call this tool with the node_id to record the fingerprint. By default, does NOT overwrite existing fingerprints — use force=true to replace them. Use save_nav_graph to persist changes to disk.",
        inputSchema: JSONSchema(
            properties: [
                "node_id": .init(
                    type: "string",
                    description: "The node ID in the graph to associate this fingerprint with (required)."
                ),
                "force": .init(
                    type: "boolean",
                    description: "Overwrite an existing fingerprint. Defaults to false to protect pre-defined fingerprints."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ],
            required: ["node_id"]
        ),
        category: .navigation
    )

    await registry.register(manifest: manifest) { args in
        guard await navGraph.isLoaded() else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No navigation graph loaded. Use load_nav_graph first."
            ))
        }

        guard case .string(let nodeId) = args["node_id"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: node_id"
            ))
        }

        guard await navGraph.getNode(nodeId) != nil else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Unknown node '\(nodeId)'. Use get_nav_graph to see available nodes."
            ))
        }

        var force = false
        if case .bool(let f) = args["force"] { force = f }

        // Check for existing fingerprint before doing the capture
        if !force, let existing = await navGraph.getNode(nodeId), existing.fingerprint != nil {
            return .success(ToolResult(
                content: "Node '\(nodeId)' already has a fingerprint. Use force=true to overwrite it, or save_nav_graph to persist the current graph."
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

        // Capture the accessibility tree
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

        // Parse the tree to extract fingerprint data
        guard let data = treeOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .error(ToolError(
                code: .commandFailed,
                message: "Failed to parse accessibility tree output as JSON."
            ))
        }

        var accessibilityIds: [String] = []
        var staticTexts: [String] = []
        collectFingerprintData(from: json, ids: &accessibilityIds, texts: &staticTexts)

        // Build fingerprint: use the first accessibility ID as the root identifier,
        // and the most common static text as the dominant text
        let rootId = accessibilityIds.first
        let dominantText = mostFrequent(staticTexts)

        guard rootId != nil || dominantText != nil else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Could not extract any fingerprint data from the current screen. The screen may lack accessibility identifiers and static text.",
                details: "Accessibility IDs found: \(accessibilityIds.count), Static texts found: \(staticTexts.count)"
            ))
        }

        let fingerprint = NavGraphStore.NodeFingerprint(
            accessibilityId: rootId,
            hierarchyHash: nil,
            dominantStaticText: dominantText
        )

        let didSet = await navGraph.setFingerprint(
            nodeId: nodeId,
            fingerprint: fingerprint,
            force: force
        )

        guard didSet else {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to set fingerprint on node '\(nodeId)'."
            ))
        }

        var output = "Fingerprint captured for node '\(nodeId)':\n"
        if let id = rootId {
            output += "  accessibilityId: \(id)\n"
        }
        if let text = dominantText {
            output += "  dominantStaticText: \(text)\n"
        }
        output += "\nThis fingerprint is in memory only. Use save_nav_graph to persist it to disk."

        return .success(ToolResult(
            content: output,
            nextSteps: [
                NextStep(
                    tool: "save_nav_graph",
                    description: "Persist the updated graph with fingerprints to disk"
                ),
            ]
        ))
    }
}

// MARK: - Helpers

private func collectFingerprintData(
    from nodes: [[String: Any]],
    ids: inout [String],
    texts: inout [String]
) {
    for node in nodes {
        if let uid = node["AXUniqueId"] as? String, !uid.isEmpty {
            ids.append(uid)
        }
        if let role = node["AXRole"] as? String, role == "AXStaticText",
           let value = node["AXValue"] as? String, !value.isEmpty {
            texts.append(value)
        }
        if let children = node["children"] as? [[String: Any]] {
            collectFingerprintData(from: children, ids: &ids, texts: &texts)
        }
    }
}

private func mostFrequent(_ items: [String]) -> String? {
    guard !items.isEmpty else { return nil }
    var counts: [String: Int] = [:]
    for item in items { counts[item, default: 0] += 1 }
    return counts.max(by: { $0.value < $1.value })?.key
}
