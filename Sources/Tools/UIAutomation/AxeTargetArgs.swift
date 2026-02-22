//
//  AxeTargetArgs.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

/// Convert accessibility targeting parameters into axe CLI flags.
///
/// Priority: `accessibility_id` > `accessibility_label` > `(x, y)` coordinates.
/// Returns `invalidInput` if no targeting info is provided.
func resolveAxeTarget(from args: [String: Value]) -> Result<[String], ToolError> {
    // Prefer accessibility_id
    if case .string(let id) = args["accessibility_id"], !id.isEmpty {
        return .success(["--identifier", id])
    }

    // Fall back to accessibility_label
    if case .string(let label) = args["accessibility_label"], !label.isEmpty {
        return .success(["--label", label])
    }

    // Fall back to x+y coordinates (accept both .int and .double)
    let x = extractNumber(from: args["x"])
    let y = extractNumber(from: args["y"])

    if let x, let y {
        return .success(["--x", "\(Int(x))", "--y", "\(Int(y))"])
    }

    return .failure(ToolError(
        code: .invalidInput,
        message: "No target specified. Provide accessibility_id, accessibility_label, or x+y coordinates."
    ))
}

/// Extract a numeric value from a MCP Value, handling both `.int` and `.double`.
private func extractNumber(from value: Value?) -> Double? {
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
