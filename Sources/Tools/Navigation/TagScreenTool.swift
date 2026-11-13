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
        description: "Capture the current screen's accessibility fingerprint and associate it with a node in the loaded navigation graph. Navigate to a screen first, then call this tool with the node_id. Prefer passing accessibility_id with an identifier unique to this screen (e.g. the screen's root view). Otherwise the first ID not used by another node's fingerprint and not seen on another screen tagged this session is chosen; tag several screens in one session so shared UI (tab bars, navigation bars, banners) can be told apart. The response lists screen-specific candidates and warns when another node's fingerprint also matches this screen. By default, does NOT overwrite existing fingerprints — use force=true to replace them. Use save_nav_graph to persist changes to disk.",
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
                "accessibility_id": .init(
                    type: "string",
                    description: "Accessibility identifier unique to this screen. Must be present on the current screen."
                ),
                "static_text": .init(
                    type: "string",
                    description: "Static text that identifies this screen (medium-confidence fallback). Must be visible on the current screen. Defaults to the first text not seen on other screens tagged this session."
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

        let snapshot: ScreenSnapshot
        switch await captureScreenSnapshot(udid: resolvedUDID, executor: executor) {
        case .success(let captured): snapshot = captured
        case .failure(let error): return .error(error)
        }

        var requestedId: String?
        if case .string(let id) = args["accessibility_id"], !id.isEmpty { requestedId = id }
        var requestedText: String?
        if case .string(let text) = args["static_text"], !text.isEmpty { requestedText = text }

        if let requestedId, !snapshot.accessibilityIdSet.contains(requestedId) {
            return .error(ToolError(
                code: .invalidInput,
                message: "accessibility_id '\(requestedId)' is not on the current screen.",
                details: "IDs on screen: \(snapshot.accessibilityIds.prefix(30).joined(separator: ", "))"
            ))
        }
        if let requestedText, !snapshot.staticTexts.contains(requestedText) {
            return .error(ToolError(
                code: .invalidInput,
                message: "static_text '\(requestedText)' is not on the current screen.",
                details: "Texts on screen: \(snapshot.uniqueStaticTexts.prefix(30).joined(separator: ", "))"
            ))
        }

        // Without explicit values, skip elements other nodes' fingerprints use
        // or that other tagged screens showed: those are shared UI and would
        // make where_am_i ambiguous or wrong.
        let claimed = await navGraph.fingerprintsClaimed(excluding: nodeId)
        let elsewhere = await navGraph.elementsObservedOnOtherScreens(excluding: nodeId)
        let sharedIds = claimed.accessibilityIds.union(elsewhere.accessibilityIds)
        let sharedTexts = claimed.staticTexts.union(elsewhere.staticTexts)
        let rootId = requestedId ?? snapshot.accessibilityIds.first { !sharedIds.contains($0) }
        let dominantText = requestedText ?? snapshot.uniqueStaticTexts.first { !sharedTexts.contains($0) }

        guard rootId != nil || dominantText != nil else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Could not extract any fingerprint data from the current screen. The screen may lack accessibility identifiers and static text.",
                details: snapshot.accessibilityIds.isEmpty && snapshot.staticTexts.isEmpty
                    ? "The accessibility tree has no identifiers or static text."
                    : "Every accessibility ID (\(snapshot.accessibilityIds.count)) and static text (\(snapshot.uniqueStaticTexts.count)) on this screen is used by another node's fingerprint or was seen on another tagged screen. Pass accessibility_id or static_text explicitly."
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

        await navGraph.recordObservedScreen(
            nodeId: nodeId,
            accessibilityIds: snapshot.accessibilityIdSet,
            staticTexts: Set(snapshot.staticTexts)
        )
        let conflicts = await navGraph.fingerprintMatches(
            accessibilityIds: snapshot.accessibilityIdSet,
            staticTexts: snapshot.staticTexts
        ).filter { $0.nodeId != nodeId }

        var output = "Fingerprint captured for node '\(nodeId)':\n"
        if let id = rootId {
            output += "  accessibilityId: \(id)\(requestedId == nil ? " (auto-selected)" : "")\n"
        }
        if let text = dominantText {
            output += "  dominantStaticText: \(text)\(requestedText == nil ? " (auto-selected)" : "")\n"
        }
        if rootId == nil {
            output += "  No accessibility ID on this screen is screen-specific, so the fingerprint uses text only (medium confidence).\n"
        }
        if requestedId == nil {
            let candidates = snapshot.accessibilityIds.filter { $0 != rootId && !sharedIds.contains($0) }
            let sharedCount = snapshot.accessibilityIds.filter { sharedIds.contains($0) }.count
            if !candidates.isEmpty {
                output += "\nOther screen-specific candidates: \(candidates.prefix(20).joined(separator: ", "))\n"
            }
            if sharedCount > 0 {
                output += "Skipped \(sharedCount) ID(s) used by other fingerprints or seen on other tagged screens.\n"
            }
            if elsewhere.accessibilityIds.isEmpty {
                output += "No other screens have been tagged this session, so shared UI such as tab bars can't be ruled out yet. Check this choice after tagging more screens.\n"
            }
        }
        if !conflicts.isEmpty {
            output += "\nWarning: these nodes' fingerprints also match this screen, so where_am_i can confuse them with '\(nodeId)':\n"
            for conflict in conflicts {
                output += "  - \(conflict.nodeId) (\(conflict.confidence)). Re-tag it on its own screen with force=true and an ID or text this screen doesn't have.\n"
            }
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
