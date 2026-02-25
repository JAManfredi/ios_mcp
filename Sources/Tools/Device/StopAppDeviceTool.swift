//
//  StopAppDeviceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStopAppDeviceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "stop_app_device",
        description: "Stop a running app on a physical iOS device. Note: devicectl does not provide a direct process termination API; this uses a best-effort approach.",
        inputSchema: JSONSchema(
            properties: [
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
                "bundle_id": .init(type: "string", description: "App bundle identifier. Falls back to session default."),
            ]
        ),
        category: .device
    )

    await registry.register(manifest: manifest) { args in
        let bundleID: String?
        if case .string(let bid) = args["bundle_id"] { bundleID = bid }
        else { bundleID = await session.get(.bundleID) }

        guard let bundleID else {
            return .error(ToolError(code: .invalidInput, message: "No bundle_id specified and no session default set."))
        }

        switch await resolveDeviceUDID(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let udid):
            // devicectl does not have a direct "stop process" command as of Xcode 16.
            // We attempt to use `devicectl device process terminate` if available.
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["devicectl", "device", "process", "terminate", "--device", udid, bundleID],
                    timeout: 15,
                    environment: nil
                )

                if result.succeeded {
                    return .success(ToolResult(content: "App stopped on device.\nDevice: \(udid)\nBundle ID: \(bundleID)"))
                } else {
                    return .success(ToolResult(
                        content: "Could not stop app on device (devicectl may not support process termination in this Xcode version).\nDevice: \(udid)\nBundle ID: \(bundleID)\nNote: You may need to stop the app manually on the device."
                    ))
                }
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to stop app: \(error.localizedDescription)"
                ))
            }
        }
    }
}
