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
        description: "Navigate to a target screen using the loaded navigation graph. Computes the shortest path from the current (or specified) node and executes each edge's actions in order: deeplinks open URLs via simctl, taps, swipes, and typing use axe. When several edges lead to the target, the one that best fits the supplied parameters is used; pass 'via' to pick one explicitly (see get_nav_graph include_edges=true for edge IDs, URLs, and parameters). Returns the sequence of actions taken. Requires a loaded nav graph (use load_nav_graph first).",
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
                    description: "JSON object of parameter substitutions for {placeholders} in edge templates (e.g. {\"eventId\": \"12345\"}). Values are percent-encoded for deeplink URLs; values that already contain '%' are treated as pre-encoded."
                ),
                "via": .init(
                    type: "string",
                    description: "Use this specific edge into the target, by edge ID or exact deeplink URL template (e.g. \"myapp://search/{query}\"). The edge must lead directly to the target."
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
        if case .string(let paramJSON) = args["parameters"] {
            switch parseParameters(paramJSON) {
            case .success(let parsed): params = parsed
            case .failure(let error): return .error(error)
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
                navGraph: navGraph,
                udid: resolvedUDID,
                executor: executor
            )
            fromNode = detected
        }

        guard let origin = fromNode else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Could not determine current screen. Provide the 'from' parameter or ensure the graph has fingerprints that identify exactly one screen.",
                details: "Tip: Use where_am_i to identify the current screen, then pass it as 'from'."
            ))
        }

        // If already at target, report success
        if origin == target {
            return .success(ToolResult(content: "Already at target node '\(target)'."))
        }

        let path: [NavGraphStore.NavEdge]
        if case .string(let via) = args["via"], !via.isEmpty {
            let direct = await navGraph.directEdges(from: origin, to: target)
            guard let chosen = direct.first(where: { $0.matches(selector: via) }) else {
                let available = direct.map(\.label)
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No edge '\(via)' leads directly from '\(origin)' to '\(target)'.",
                    details: available.isEmpty
                        ? "No edges lead directly to '\(target)' from '\(origin)'."
                        : "Edges to '\(target)': \(available.joined(separator: ", "))"
                ))
            }
            path = [chosen]
        } else {
            // Compute shortest path via BFS
            guard let found = await navGraph.shortestPath(
                from: origin,
                to: target,
                providedParameters: Set(params.keys)
            ) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No path found from '\(origin)' to '\(target)'.",
                    details: "The graph has no edge sequence connecting these nodes. Use get_nav_graph to inspect the graph structure."
                ))
            }
            path = found
        }

        // Execute each edge's actions in sequence
        var log: [String] = ["Path: \(origin) → \(path.map { $0.to ?? "?" }.joined(separator: " → "))"]
        var actionCount = 0

        for (edgeIndex, edge) in path.enumerated() {
            let edgeTarget = edge.to ?? "(action only)"
            log.append("\nEdge \(edgeIndex + 1): \(edge.from) → \(edgeTarget) [\(edge.label)]")
            if let preconditions = edge.preconditions, !preconditions.isEmpty {
                log.append("  Preconditions (not checked): \(preconditions.joined(separator: ", "))")
            }

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

    // Substitute template parameters: {param_name} → percent-encoded value
    for (key, value) in params {
        url = url.replacingOccurrences(of: "{\(key)}", with: percentEncodedPathValue(value))
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
            return .failure(axeCommandError("axe tap failed", stderr: result.stderr))
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
            return .failure(axeCommandError("axe swipe failed", stderr: result.stderr))
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

    // Focus the target field first when the edge names one; `axe type` types into the focused element.
    var focused = ""
    if action.target != nil {
        switch await executeTap(action, udid: udid, executor: executor) {
        case .success(let message): focused = " after \(message.prefix(1).lowercased() + message.dropFirst())"
        case .failure(let error): return .failure(error)
        }
    }

    let axeArgs = ["type", text, "--udid", udid]

    do {
        let result = try await executor.execute(
            executable: resolvedAxe,
            arguments: axeArgs,
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(axeCommandError("axe type failed", stderr: result.stderr))
        }

        return .success("Typed '\(text)'\(focused)")
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

/// Identify the current node from its fingerprint. Returns nil when nothing
/// matches or several nodes match equally well.
private func detectCurrentNode(
    navGraph: NavGraphStore,
    udid: String,
    executor: any CommandExecuting
) async -> String? {
    guard case .success(let snapshot) = await captureScreenSnapshot(udid: udid, executor: executor) else { return nil }
    let match = await navGraph.matchFingerprint(
        accessibilityIds: snapshot.accessibilityIdSet,
        staticTexts: snapshot.staticTexts
    )
    return match?.nodeId
}

/// Parse the `parameters` argument: a JSON object of scalar values.
/// Booleans become "true"/"false"; numbers use their JSON form.
func parseParameters(_ json: String) -> Result<[String: String], ToolError> {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let parsed = object as? [String: Any] else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "'parameters' must be a JSON object, e.g. {\"eventId\": \"12345\"}."
        ))
    }

    var params: [String: String] = [:]
    for (key, value) in parsed {
        switch value {
        case let string as String:
            params[key] = string
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            params[key] = number.boolValue ? "true" : "false"
        case let number as NSNumber:
            params[key] = number.stringValue
        default:
            return .failure(ToolError(
                code: .invalidInput,
                message: "Parameter '\(key)' must be a string, number, or boolean."
            ))
        }
    }
    return .success(params)
}

/// Percent-encode a value for substitution into a URL path segment.
/// `/`, `?`, and `#` are encoded so a value can't change the URL's structure;
/// `%` is left alone so already-encoded values aren't double-encoded.
func percentEncodedPathValue(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#")
    allowed.insert("%")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func extractSettleMs(from value: Value?) -> Int {
    guard let value else { return 1000 }
    switch value {
    case .int(let i): return i
    case .double(let d): return Int(d)
    default: return 1000
    }
}
