//
//  AxeTargetArgs.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

/// Convert accessibility targeting parameters into axe CLI flags.
///
/// Priority: `accessibility_id` > `accessibility_label` > `(x, y)` coordinates.
/// Returns `invalidInput` if no targeting info is provided.
func resolveAxeTarget(from args: [String: Value]) -> Result<[String], ToolError> {
    if case .string(let id) = args["accessibility_id"], !id.isEmpty {
        return .success(["--id", id])
    }

    if case .string(let label) = args["accessibility_label"], !label.isEmpty {
        return .success(["--label", label])
    }

    let x = extractNumber(from: args["x"])
    let y = extractNumber(from: args["y"])

    if let x, let y {
        return .success(["-x", "\(Int(x))", "-y", "\(Int(y))"])
    }

    return .failure(ToolError(
        code: .invalidInput,
        message: "No target specified. Provide accessibility_id, accessibility_label, or x+y coordinates."
    ))
}

/// Resolve targeting parameters to concrete coordinates.
///
/// If `x`/`y` are provided directly, returns them. Otherwise runs `axe describe-ui`
/// to find the element by `accessibility_id` or `accessibility_label` and returns
/// the center of its frame.
func resolveTargetCoordinates(
    from args: [String: Value],
    axePath: String,
    udid: String,
    executor: any CommandExecuting
) async -> Result<(x: Double, y: Double), ToolError> {
    let x = extractNumber(from: args["x"])
    let y = extractNumber(from: args["y"])
    if let x, let y { return .success((x: x, y: y)) }

    var identifier: String?
    var label: String?

    if case .string(let id) = args["accessibility_id"], !id.isEmpty {
        identifier = id
    } else if case .string(let l) = args["accessibility_label"], !l.isEmpty {
        label = l
    }

    guard identifier != nil || label != nil else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No target specified. Provide accessibility_id, accessibility_label, or x+y coordinates."
        ))
    }

    do {
        let result = try await executor.execute(
            executable: axePath,
            arguments: ["describe-ui", "--udid", udid],
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "Failed to resolve target element: axe describe-ui failed",
                details: result.stderr
            ))
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "Failed to parse accessibility tree from axe describe-ui"
            ))
        }

        for root in json {
            if let center = findElementCenter(in: root, identifier: identifier, label: label) {
                return .success(center)
            }
        }

        let target = identifier ?? label ?? "unknown"
        return .failure(ToolError(
            code: .invalidInput,
            message: "Element not found in accessibility tree: \(target). Use snapshot_ui to inspect available elements, or provide x/y coordinates."
        ))
    } catch let error as ToolError {
        return .failure(error)
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to resolve target coordinates: \(error.localizedDescription)"
        ))
    }
}

private func findElementCenter(
    in node: [String: Any],
    identifier: String?,
    label: String?
) -> (x: Double, y: Double)? {
    if let identifier, let uid = node["AXUniqueId"] as? String, uid == identifier {
        return extractCenter(from: node)
    }
    if let label, let axLabel = node["AXLabel"] as? String, axLabel == label {
        return extractCenter(from: node)
    }

    if let children = node["children"] as? [[String: Any]] {
        for child in children {
            if let center = findElementCenter(in: child, identifier: identifier, label: label) {
                return center
            }
        }
    }

    return nil
}

private func extractCenter(from node: [String: Any]) -> (x: Double, y: Double)? {
    guard let frame = node["frame"] as? [String: Any],
          let x = frame["x"] as? Double,
          let y = frame["y"] as? Double,
          let width = frame["width"] as? Double,
          let height = frame["height"] as? Double else { return nil }
    return (x: x + width / 2.0, y: y + height / 2.0)
}

/// Resolve screen center by reading the root Application frame from `describe-ui`.
func resolveScreenCenter(
    axePath: String,
    udid: String,
    executor: any CommandExecuting
) async -> Result<(x: Double, y: Double), ToolError> {
    do {
        let result = try await executor.execute(
            executable: axePath,
            arguments: ["describe-ui", "--udid", udid],
            timeout: 120,
            environment: nil
        )

        guard result.succeeded else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "Failed to resolve screen dimensions: axe describe-ui failed",
                details: result.stderr
            ))
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let root = json.first,
              let frame = root["frame"] as? [String: Any],
              let width = frame["width"] as? Double,
              let height = frame["height"] as? Double else {
            return .failure(ToolError(
                code: .commandFailed,
                message: "Failed to parse screen dimensions from axe describe-ui"
            ))
        }

        return .success((x: width / 2.0, y: height / 2.0))
    } catch let error as ToolError {
        return .failure(error)
    } catch {
        return .failure(ToolError(
            code: .internalError,
            message: "Failed to resolve screen center: \(error.localizedDescription)"
        ))
    }
}

/// Extract a numeric value from a MCP Value, handling both `.int` and `.double`.
func extractNumber(from value: Value?) -> Double? {
    guard let value else { return nil }
    switch value {
    case .int(let i):
        return Double(i)
    case .double(let d):
        return d
    default:
        return nil
    }
}
