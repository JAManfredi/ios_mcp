//
//  SimulatorArgResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

/// Resolves and validates the simulator UDID from the `udid` argument or the
/// session default.
func resolveSimulatorUDID(
    from args: [String: Value],
    session: SessionStore,
    validator: DefaultsValidator
) async -> Result<String, ToolError> {
    let udid: String?
    if case .string(let explicit) = args["udid"] {
        udid = explicit
    } else {
        udid = await session.get(.simulatorUDID)
    }

    guard let udid else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No simulator UDID provided, and no session default is set. Run list_simulators first."
        ))
    }

    if let error = await validator.validateSimulatorUDID(udid) {
        return .failure(error)
    }
    return .success(udid)
}
