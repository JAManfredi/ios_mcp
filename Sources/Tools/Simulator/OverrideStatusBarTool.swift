//
//  OverrideStatusBarTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerOverrideStatusBarTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "override_status_bar",
        description: "Override the iOS simulator status bar values (time, battery, cellular, Wi-Fi). Useful for clean screenshots. At least one override parameter is required, or pass clear: true to reset all overrides. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "time": .init(
                    type: "string",
                    description: "Time string to display (e.g. '9:41')."
                ),
                "battery_level": .init(
                    type: "number",
                    description: "Battery level percentage (0-100)."
                ),
                "cellular_bars": .init(
                    type: "number",
                    description: "Number of cellular signal bars (0-4)."
                ),
                "wifi_bars": .init(
                    type: "number",
                    description: "Number of Wi-Fi signal bars (0-3)."
                ),
                "clear": .init(
                    type: "boolean",
                    description: "Set to true to clear all status bar overrides."
                ),
            ]
        ),
        category: .simulator
    )

    await registry.register(manifest: manifest) { args in
        do {
            let udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            } else {
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

            let shouldClear: Bool
            if case .bool(let c) = args["clear"] {
                shouldClear = c
            } else {
                shouldClear = false
            }

            if shouldClear {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "status_bar", resolvedUDID, "clear"],
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl status_bar clear failed",
                        details: result.stderr
                    ))
                }

                return .success(ToolResult(
                    content: "Status bar overrides cleared on simulator \(resolvedUDID)."
                ))
            }

            var overrideArgs: [String] = ["simctl", "status_bar", resolvedUDID, "override"]

            if case .string(let time) = args["time"] {
                overrideArgs.append(contentsOf: ["--time", time])
            }

            if let batteryLevel = extractInt(from: args["battery_level"]) {
                let clamped = min(max(batteryLevel, 0), 100)
                overrideArgs.append(contentsOf: ["--batteryLevel", "\(clamped)"])
            }

            if let cellularBars = extractInt(from: args["cellular_bars"]) {
                let clamped = min(max(cellularBars, 0), 4)
                overrideArgs.append(contentsOf: ["--cellularBars", "\(clamped)"])
            }

            if let wifiBars = extractInt(from: args["wifi_bars"]) {
                let clamped = min(max(wifiBars, 0), 3)
                overrideArgs.append(contentsOf: ["--wifiBars", "\(clamped)"])
            }

            // Must have at least one override flag beyond the base command
            guard overrideArgs.count > 4 else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "At least one status bar override (time, battery_level, cellular_bars, wifi_bars) or clear: true is required."
                ))
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: overrideArgs,
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl status_bar override failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Status bar overridden on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to override status bar: \(error.localizedDescription)"
            ))
        }
    }
}

private func extractInt(from value: Value?) -> Int? {
    guard let value else { return nil }
    switch value {
    case .int(let v): return v
    case .double(let v): return Int(v)
    default: return nil
    }
}
