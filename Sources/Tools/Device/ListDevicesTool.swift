//
//  ListDevicesTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerListDevicesTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "list_devices",
        description: "List connected physical iOS devices. Automatically sets session device_udid when exactly one device is connected.",
        inputSchema: JSONSchema(),
        category: .device,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { _ in
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["devicectl", "list", "devices", "--json-output", "-"],
                timeout: 15,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "devicectl list devices failed. Ensure Xcode 15+ is installed and selected with xcode-select.",
                    details: result.stderr
                ))
            }

            guard let devices = DeviceIdentity.physicalDevices(fromDevicectlJSON: result.stdout) else {
                return .success(ToolResult(content: "No devices found or unable to parse devicectl output."))
            }

            if devices.isEmpty {
                return .success(ToolResult(content: "No physical devices connected."))
            }

            var lines: [String] = ["Connected devices (\(devices.count)):"]

            for device in devices {
                let name = DeviceIdentity.name(for: device) ?? "Unknown"
                let osVersion = DeviceIdentity.osVersion(for: device) ?? "?"
                let model = DeviceIdentity.model(for: device) ?? "Unknown"
                let transportType = DeviceIdentity.transportType(for: device) ?? "?"

                let identifier = DeviceIdentity.destinationUDID(for: device) ?? "unidentified"
                lines.append(
                    "  \(identifier) — \(name) (\(model), iOS \(osVersion), \(transportType))"
                )
            }

            // Auto-set session default if exactly one device, and only when it
            // actually has an identifier — storing a placeholder would fail
            // every later device call with a confusing "not found".
            if devices.count == 1,
               let device = devices.first,
               let udid = DeviceIdentity.destinationUDID(for: device) {
                await session.set(.deviceUDID, value: udid)
                lines.append("\nSession default set: device_udid = \(udid)")
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to list devices: \(error.localizedDescription)"
            ))
        }
    }

}
