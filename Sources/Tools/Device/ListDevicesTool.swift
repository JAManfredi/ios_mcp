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
                    message: "devicectl list devices failed. Ensure Xcode 16+ is installed.",
                    details: result.stderr
                ))
            }

            guard let data = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resultObj = json["result"] as? [String: Any],
                  let devices = resultObj["devices"] as? [[String: Any]] else {
                return .success(ToolResult(content: "No devices found or unable to parse devicectl output."))
            }

            if devices.isEmpty {
                return .success(ToolResult(content: "No physical devices connected."))
            }

            var lines: [String] = ["Connected devices (\(devices.count)):"]

            for device in devices {
                let identifier = device["identifier"] as? String ?? "?"
                let deviceProps = device["deviceProperties"] as? [String: Any]
                let name = deviceProps?["name"] as? String ?? "Unknown"
                let osVersion = deviceProps?["osVersionNumber"] as? String ?? "?"
                let hardwareProps = device["hardwareProperties"] as? [String: Any]
                let model = hardwareProps?["marketingName"] as? String
                    ?? hardwareProps?["productType"] as? String
                    ?? "Unknown"
                let connectionProps = device["connectionProperties"] as? [String: Any]
                let transportType = connectionProps?["transportType"] as? String ?? "?"

                lines.append("  \(identifier) — \(name) (\(model), iOS \(osVersion), \(transportType))")
            }

            // Auto-set session default if exactly one device
            if devices.count == 1, let udid = devices.first?["identifier"] as? String {
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
