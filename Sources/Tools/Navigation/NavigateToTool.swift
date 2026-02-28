//
//  NavigateToTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerNavigateToTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    navGraph: NavGraphStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "navigate_to",
        description: "Navigate to a target screen using the loaded navigation graph. Computes the shortest path from the current (or specified) node and executes each edge's actions in order: deeplinks open URLs via simctl, taps and swipes use axe. Returns the sequence of actions taken. Requires a loaded nav graph (use load_nav_graph first).",
        inputSchema: JSONSchema(
            properties: [
                "target": .init(
                    type: "string",
                    description: "The target node ID to navigate to (required)."
                ),
                "from": .init(
                    type: "string",
                    description: "The current node ID. If omitted, uses where_am_i to detect the current screen."
                ),
                "parameters": .init(
                    type: "string",
                    description: "JSON object of parameter substitutions for deeplink templates (e.g. {\"event_id\": \"12345\"})."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "settle_ms": .init(
                    type: "number",
                    description: "Milliseconds to wait between actions for UI to settle. Defaults to 1000."
                ),
            ],
            required: ["target"]
        ),
        category: .navigation,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        guard await navGraph.isLoaded() else {
            return .success(ToolResult(
                content: "No navigation graph is loaded. Use inspect_ui to see the current screen, then tap, swipe, or deep_link to navigate manually.",
                nextSteps: [
                    NextStep(
                        tool: "inspect_ui",
                        description: "Capture the accessibility tree to find interactive elements"
                    ),
                    NextStep(
                        tool: "load_nav_graph",
                        description: "Load a navigation graph if one is available"
                    ),
                ]
            ))
        }

        guard case .string(let target) = args["target"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: target"
            ))
        }

        guard await navGraph.getNode(target) != nil else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Unknown target node '\(target)'. Use get_nav_graph to see available nodes."
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

        // Parse parameter substitutions
        var params: [String: String] = [:]
        if case .string(let paramJSON) = args["parameters"],
           let data = paramJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed {
                params[key] = "\(value)"
            }
        }

        let settleMs = extractSettleMs(from: args["settle_ms"])

        // Determine the "from" node
        var fromNode: String?
        if case .string(let f) = args["from"] {
            fromNode = f
        }

        // If no "from" specified, try fingerprint detection via inspect_ui
        if fromNode == nil {
            let detected = await detectCurrentNode(
                registry: registry,
                navGraph: navGraph,
                udid: resolvedUDID
            )
            fromNode = detected
        }

        guard let origin = fromNode else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Could not determine current screen. Provide the 'from' parameter or ensure the graph has fingerprints for screen detection.",
                details: "Tip: Use where_am_i to identify the current screen, then pass it as 'from'."
            ))
        }

        // If already at target, report success
        if origin == target {
            return .success(ToolResult(content: "Already at target node '\(target)'."))
        }

        // Compute shortest path via BFS
        guard let path = await navGraph.shortestPath(from: origin, to: target) else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No path found from '\(origin)' to '\(target)'.",
                details: "The graph has no edge sequence connecting these nodes. Use get_nav_graph to inspect the graph structure."
            ))
        }

        // Execute each edge's actions in sequence
        var log: [String] = ["Path: \(origin) → \(path.map { $0.to ?? "?" }.joined(separator: " → "))"]
        var actionCount = 0

        for (edgeIndex, edge) in path.enumerated() {
            let edgeTarget = edge.to ?? "(action only)"
            log.append("\nEdge \(edgeIndex + 1): \(edge.from) → \(edgeTarget)")

            for action in edge.actions {
                actionCount += 1
                let result = await executeAction(
                    action,
                    params: params,
                    udid: resolvedUDID,
                    executor: executor,
                    session: session
                )

                switch result {
                case .success(let msg):
                    log.append("  [\(action.type.rawValue)] \(msg)")
                case .failure(let error):
                    log.append("  [\(action.type.rawValue)] FAILED: \(error.message)")
                    let output = log.joined(separator: "\n")
                    return .error(ToolError(
                        code: error.code,
                        message: "Navigation failed at edge \(edgeIndex + 1), action '\(action.type.rawValue)': \(error.message)",
                        details: output
                    ))
                }

                // Settle between actions to let UI update
                if settleMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(settleMs) * 1_000_000)
                }
            }
        }

        log.append("\nNavigation complete: \(actionCount) action(s) executed.")

        return .success(ToolResult(
            content: log.joined(separator: "\n"),
            nextSteps: [
                NextStep(
                    tool: "where_am_i",
                    description: "Verify the current screen matches the target"
                ),
                NextStep(
                    tool: "inspect_ui",
                    description: "Inspect the UI elements on the target screen"
                ),
            ]
        ))
    }
}

// MARK: - Action Execution

private func executeAction(
    _ action: NavGraphStore.EdgeAction,
    params: [String: String],
    udid: String,
    executor: any CommandExecuting,
    session: SessionStore
) async -> Result<String, ToolError> {
    switch action.type {
    case .deeplink:
        return await executeDeeplink(action, params: params, udid: udid, executor: executor)
    case .tap:
        return await executeTap(action, udid: udid, executor: executor)
    case .swipe:
        return await executeSwipe(action, udid: udid, executor: executor)
    case .typeText:
        return await executeTypeText(action, params: params, udid: udid, executor: executor)
    case .keyPress:
        return await executeKeyPress(action, udid: udid, executor: executor)
    }
}

private func executeDeeplink(
    _ action: NavGraphStore.EdgeAction,
    params: [String: String],
    udid: String,
    executor: any CommandExecuting
) async -> Result<String, ToolError> {
    guard var url = action.url else {
        return .failure(ToolError(code: .invalidInput, message: "Deeplink action missing 'url' field."))
    }

    // Substitute template parameters: {param_name} → value
    for (key, value) in params {
        url = url.replacingOccurrences(of: "{\(key)}", with: value)
    }

    // Warn if unresolved placeholders remain
    if url.contains("{") {
        let unresolved = url.components(separatedBy: "{")
            .dropFirst()
            .compactMap { $0.components(separatedBy: "}").first }
        return .failure(ToolError(
            code: .invalidInput,
            message: "Unresolved template parameters: \(unresolved.joined(separator: ", ")). Provide them via the 'parameters' argument."
        ))
    }

    do {
        let result = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "openurl", udid, url],
            timeout: 60,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "simctl openurl failed: \(result.stderr)"
            ))
        }

        return .success("Opened \(url)")
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to open deeplink: \(error.localizedDescription)"
        ))
    }
}

private func executeTap(
    _ action: NavGraphStore.EdgeAction,
    udid: String,
    executor: any CommandExecuting
) async -> Result<String, ToolError> {
    let resolvedAxe: String
    switch resolveAxePath() {
    case .success(let path): resolvedAxe = path
    case .failure(let error): return .failure(error)
    }

    guard let target = action.target else {
        return .failure(ToolError(code: .invalidInput, message: "Tap action missing 'target' field."))
    }

    var axeArgs = ["tap", "--udid", udid]
    var targetDesc = ""

    if let id = target.accessibilityId, !id.isEmpty {
        axeArgs += ["--id", id]
        targetDesc = "id=\(id)"
    } else if let label = target.accessibilityLabel, !label.isEmpty {
        axeArgs += ["--label", label]
        targetDesc = "label=\(label)"
    } else if let x = target.x, let y = target.y {
        axeArgs += ["-x", "\(Int(x))", "-y", "\(Int(y))"]
        targetDesc = "(\(Int(x)), \(Int(y)))"
    } else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "Tap target has no accessibility_id, label, or coordinates."
        ))
    }

    do {
        let result = try await executor.execute(
            executable: resolvedAxe,
            arguments: axeArgs,
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "axe tap failed: \(result.stderr)"
            ))
        }

        return .success("Tapped \(targetDesc)")
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to tap: \(error.localizedDescription)"
        ))
    }
}

private func executeSwipe(
    _ action: NavGraphStore.EdgeAction,
    udid: String,
    executor: any CommandExecuting
) async -> Result<String, ToolError> {
    let resolvedAxe: String
    switch resolveAxePath() {
    case .success(let path): resolvedAxe = path
    case .failure(let error): return .failure(error)
    }

    guard let direction = action.direction else {
        return .failure(ToolError(code: .invalidInput, message: "Swipe action missing 'direction' field."))
    }

    // Resolve center from target or default to screen center
    let center: (x: Double, y: Double)
    if let target = action.target, let x = target.x, let y = target.y {
        center = (x, y)
    } else {
        switch await resolveScreenCenter(axePath: resolvedAxe, udid: udid, executor: executor) {
        case .success(let c): center = c
        case .failure(let error): return .failure(error)
        }
    }

    let distance = 200.0
    let half = distance / 2.0
    let endpoints: (startX: Double, startY: Double, endX: Double, endY: Double)
    switch direction {
    case "up":    endpoints = (center.x, center.y + half, center.x, center.y - half)
    case "down":  endpoints = (center.x, center.y - half, center.x, center.y + half)
    case "left":  endpoints = (center.x + half, center.y, center.x - half, center.y)
    case "right": endpoints = (center.x - half, center.y, center.x + half, center.y)
    default:
        return .failure(ToolError(code: .invalidInput, message: "Invalid swipe direction: \(direction)"))
    }

    let axeArgs = [
        "swipe", "--udid", udid,
        "--start-x", "\(Int(endpoints.startX))",
        "--start-y", "\(Int(endpoints.startY))",
        "--end-x", "\(Int(endpoints.endX))",
        "--end-y", "\(Int(endpoints.endY))",
    ]

    do {
        let result = try await executor.execute(
            executable: resolvedAxe,
            arguments: axeArgs,
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "axe swipe failed: \(result.stderr)"
            ))
        }

        return .success("Swiped \(direction)")
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to swipe: \(error.localizedDescription)"
        ))
    }
}

private func executeTypeText(
    _ action: NavGraphStore.EdgeAction,
    params: [String: String],
    udid: String,
    executor: any CommandExecuting
) async -> Result<String, ToolError> {
    let resolvedAxe: String
    switch resolveAxePath() {
    case .success(let path): resolvedAxe = path
    case .failure(let error): return .failure(error)
    }

    guard var text = action.text else {
        return .failure(ToolError(code: .invalidInput, message: "type_text action missing 'text' field."))
    }

    // Substitute parameters in text
    for (key, value) in params {
        text = text.replacingOccurrences(of: "{\(key)}", with: value)
    }

    var axeArgs = ["type-text", "--udid", udid, "--text", text]

    if let target = action.target, let id = target.accessibilityId, !id.isEmpty {
        axeArgs += ["--id", id]
    }

    do {
        let result = try await executor.execute(
            executable: resolvedAxe,
            arguments: axeArgs,
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "axe type-text failed: \(result.stderr)"
            ))
        }

        return .success("Typed '\(text)'")
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to type text: \(error.localizedDescription)"
        ))
    }
}

private func executeKeyPress(
    _ action: NavGraphStore.EdgeAction,
    udid: String,
    executor: any CommandExecuting
) async -> Result<String, ToolError> {
    guard let key = action.key else {
        return .failure(ToolError(code: .invalidInput, message: "key_press action missing 'key' field."))
    }

    do {
        let result = try await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "io", udid, "sendkey", key],
            timeout: 60,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "simctl sendkey failed: \(result.stderr)"
            ))
        }

        return .success("Pressed '\(key)'")
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to press key: \(error.localizedDescription)"
        ))
    }
}

// MARK: - Helpers

private func detectCurrentNode(
    registry: ToolRegistry,
    navGraph: NavGraphStore,
    udid: String
) async -> String? {
    // Call inspect_ui to get the accessibility tree, then fingerprint match
    let response = try? await registry.callTool(
        name: "inspect_ui",
        arguments: ["udid": .string(udid)]
    )

    guard case .success(let result) = response else { return nil }

    // Parse accessibility IDs and static texts from the tree
    guard let data = result.content.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return nil
    }

    var accessibilityIds = Set<String>()
    var staticTexts: [String] = []
    collectFingerprint(from: json, ids: &accessibilityIds, texts: &staticTexts)

    let match = await navGraph.matchFingerprint(
        accessibilityIds: accessibilityIds,
        staticTexts: staticTexts
    )

    return match?.nodeId
}

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

private func extractSettleMs(from value: Value?) -> Int {
    guard let value else { return 1000 }
    switch value {
    case .int(let i): return i
    case .double(let d): return Int(d)
    default: return 1000
    }
}
