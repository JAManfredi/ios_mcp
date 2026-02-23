//
//  SwipeTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

private let validDirections: Set<String> = ["up", "down", "left", "right"]

func registerSwipeTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swipe",
        description: "Swipe on a UI element in the iOS simulator. Requires a direction and a target element. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "direction": .init(
                    type: "string",
                    description: "Swipe direction (required).",
                    enumValues: ["up", "down", "left", "right"]
                ),
                "distance": .init(
                    type: "number",
                    description: "Swipe distance in points (optional)."
                ),
                "accessibility_id": .init(
                    type: "string",
                    description: "Accessibility identifier of the target element (preferred)."
                ),
                "accessibility_label": .init(
                    type: "string",
                    description: "Accessibility label of the target element."
                ),
                "x": .init(
                    type: "number",
                    description: "X coordinate (used with y when no accessibility target)."
                ),
                "y": .init(
                    type: "number",
                    description: "Y coordinate (used with x when no accessibility target)."
                ),
            ],
            required: ["direction"]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        let resolvedAxe: String
        if let axePath {
            resolvedAxe = axePath
        } else {
            switch resolveAxePath() {
            case .success(let path): resolvedAxe = path
            case .failure(let error): return .error(error)
            }
        }

        guard case .string(let direction) = args["direction"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: direction"
            ))
        }

        guard validDirections.contains(direction) else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Invalid direction '\(direction)'. Must be one of: up, down, left, right."
            ))
        }

        var udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        }
        if udid == nil {
            udid = await session.get(.simulatorUDID)
        }
        guard let resolvedUDID = udid else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No simulator UDID provided, and no session default is set. Run list_simulators first."
            ))
        }

        if let error = await validator.validateSimulatorUDID(resolvedUDID) {
            return .error(error)
        }

        do {
            // Resolve swipe center: explicit target, or screen center from describe-ui
            let coords: (x: Double, y: Double)
            let hasTarget = args["accessibility_id"] != nil
                || args["accessibility_label"] != nil
                || (args["x"] != nil && args["y"] != nil)

            if hasTarget {
                switch await resolveTargetCoordinates(
                    from: args,
                    axePath: resolvedAxe,
                    udid: resolvedUDID,
                    executor: executor
                ) {
                case .success(let c): coords = c
                case .failure(let error): return .error(error)
                }
            } else {
                switch await resolveScreenCenter(
                    axePath: resolvedAxe,
                    udid: resolvedUDID,
                    executor: executor
                ) {
                case .success(let c): coords = c
                case .failure(let error): return .error(error)
                }
            }

            let distance = Double(extractSwipeDistance(from: args["distance"]) ?? 200)
            let endpoints = computeSwipeEndpoints(
                center: coords,
                direction: direction,
                distance: distance
            )

            let axeArgs = [
                "swipe", "--udid", resolvedUDID,
                "--start-x", "\(Int(endpoints.startX))",
                "--start-y", "\(Int(endpoints.startY))",
                "--end-x", "\(Int(endpoints.endX))",
                "--end-y", "\(Int(endpoints.endY))",
            ]

            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: axeArgs,
                timeout: 120,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "axe swipe failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: "Swiped \(direction) on simulator \(resolvedUDID)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to swipe: \(error.localizedDescription)"
            ))
        }
    }
}

private func extractSwipeDistance(from value: Value?) -> Int? {
    guard let value else { return nil }
    switch value {
    case .int(let i): return i
    case .double(let d): return Int(d)
    default: return nil
    }
}

private func computeSwipeEndpoints(
    center: (x: Double, y: Double),
    direction: String,
    distance: Double
) -> (startX: Double, startY: Double, endX: Double, endY: Double) {
    let half = distance / 2.0
    switch direction {
    case "up":    return (center.x, center.y + half, center.x, center.y - half)
    case "down":  return (center.x, center.y - half, center.x, center.y + half)
    case "left":  return (center.x + half, center.y, center.x - half, center.y)
    case "right": return (center.x - half, center.y, center.x + half, center.y)
    default:      return (center.x, center.y, center.x, center.y)
    }
}
