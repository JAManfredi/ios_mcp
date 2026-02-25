//
//  LaunchAppDeviceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerLaunchAppDeviceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "launch_app_device",
        description: "Launch an app on a physical iOS device via devicectl. Falls back to session defaults for device_udid and bundle_id.",
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
            let lockKey = "device:\(udid)"
            return await concurrency.withLock(key: lockKey, owner: "launch_app_device") {
                do {
                    let result = try await executor.execute(
                        executable: "/usr/bin/xcrun",
                        arguments: ["devicectl", "device", "process", "launch", "--device", udid, bundleID],
                        timeout: 30,
                        environment: nil
                    )

                    if result.succeeded {
                        return .success(ToolResult(content: "App launched on device.\nDevice: \(udid)\nBundle ID: \(bundleID)"))
                    } else {
                        return .error(ToolError(
                            code: .commandFailed,
                            message: "Failed to launch app on device.",
                            details: result.stderr
                        ))
                    }
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed to launch app: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
