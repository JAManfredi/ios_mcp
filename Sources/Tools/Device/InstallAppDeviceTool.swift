//
//  InstallAppDeviceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerInstallAppDeviceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "install_app_device",
        description: "Install an app bundle on a physical iOS device via devicectl. Requires the path to a built .app bundle.",
        inputSchema: JSONSchema(
            properties: [
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
                "app_path": .init(type: "string", description: "Path to the .app bundle to install (required)."),
            ],
            required: ["app_path"]
        ),
        category: .device
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let appPath) = args["app_path"] else {
            return .error(ToolError(code: .invalidInput, message: "app_path is required."))
        }

        switch await resolveDeviceUDID(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let udid):
            let lockKey = "device:\(udid)"
            return await concurrency.withLock(key: lockKey, owner: "install_app_device") {
                do {
                    let result = try await executor.execute(
                        executable: "/usr/bin/xcrun",
                        arguments: ["devicectl", "device", "install", "app", "--device", udid, appPath],
                        timeout: 120,
                        environment: nil
                    )

                    if result.succeeded {
                        return .success(ToolResult(content: "App installed on device.\nDevice: \(udid)\nApp: \(appPath)"))
                    } else {
                        return .error(ToolError(
                            code: .commandFailed,
                            message: "Failed to install app on device.",
                            details: result.stderr
                        ))
                    }
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed to install app: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
