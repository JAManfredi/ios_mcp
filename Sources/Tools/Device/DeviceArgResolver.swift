//
//  DeviceArgResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import MCP

/// Resolves the device UDID from explicit args or session defaults.
func resolveDeviceUDID(
    from args: [String: Value],
    session: SessionStore,
    validator: DefaultsValidator
) async -> Result<String, ToolError> {
    let udid: String?

    if case .string(let explicit) = args["device_udid"] {
        udid = explicit
    } else {
        udid = await session.get(.deviceUDID)
    }

    guard let udid else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No device UDID specified, and no session default is set. Run list_devices first."
        ))
    }

    if let error = await validator.validateDeviceUDID(udid) {
        return .failure(error)
    }

    return .success(udid)
}

/// Builds xcodebuild destination string for a physical device.
func deviceDestination(udid: String) -> String {
    "platform=iOS,id=\(udid)"
}
