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
                "operator_name": .init(
                    type: "string",
                    description: "Carrier name to display. Pass an empty string to hide it."
                ),
                "preset": .init(
                    type: "string",
                    description: "'screenshot' applies Apple's marketing look: 9:41, full charged battery, full Wi-Fi and cellular bars. Explicit parameters override preset values.",
                    enumValues: ["screenshot"]
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
            for key in ["time", "operator_name", "preset"] {
                guard let value = args[key] else { continue }
                guard case .string = value else {
                    return .error(ToolError(code: .invalidInput, message: "\(key) must be a string."))
                }
            }
            if let value = args["clear"] {
                guard case .bool = value else {
                    return .error(ToolError(code: .invalidInput, message: "clear must be a boolean."))
                }
            }
            var numbers: [String: Int] = [:]
            for key in ["battery_level", "cellular_bars", "wifi_bars"] {
                if let value = args[key] {
                    numbers[key] = try integerArgument(value, named: key).get()
                }
            }
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

            var presetFlags: [(flag: String, value: String)] = []
            if case .string(let preset) = args["preset"] {
                guard preset == "screenshot" else {
                    return .error(ToolError(code: .invalidInput, message: "preset must be 'screenshot'."))
                }
                presetFlags = screenshotStatusBarPreset
            }
            // Explicit arguments win over the preset's value for the same flag.
            var explicitFlags = Set<String>()
            for (key, flag) in [
                ("time", "--time"), ("battery_level", "--batteryLevel"), ("cellular_bars", "--cellularBars"),
                ("wifi_bars", "--wifiBars"), ("operator_name", "--operatorName"),
            ] where args[key] != nil {
                explicitFlags.insert(flag)
            }
            for (flag, value) in presetFlags where !explicitFlags.contains(flag) {
                overrideArgs.append(contentsOf: [flag, value])
            }

            if case .string(let time) = args["time"] {
                overrideArgs.append(contentsOf: ["--time", time])
            }

            if case .string(let name) = args["operator_name"] {
                overrideArgs.append(contentsOf: ["--operatorName", name])
            }

            if let batteryLevel = numbers["battery_level"] {
                let clamped = min(max(batteryLevel, 0), 100)
                overrideArgs.append(contentsOf: ["--batteryLevel", "\(clamped)"])
            }

            if let cellularBars = numbers["cellular_bars"] {
                let clamped = min(max(cellularBars, 0), 4)
                overrideArgs.append(contentsOf: ["--cellularBars", "\(clamped)"])
            }

            if let wifiBars = numbers["wifi_bars"] {
                let clamped = min(max(wifiBars, 0), 3)
                overrideArgs.append(contentsOf: ["--wifiBars", "\(clamped)"])
            }

            // Must have at least one override flag beyond the base command
            guard overrideArgs.count > 4 else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "At least one status bar override (time, battery_level, cellular_bars, wifi_bars, operator_name, preset) or clear: true is required."
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

/// Apple's marketing status bar, as used in App Store screenshots.
let screenshotStatusBarPreset: [(flag: String, value: String)] = [
    ("--time", "9:41"),
    ("--dataNetwork", "wifi"),
    ("--wifiMode", "active"),
    ("--wifiBars", "3"),
    ("--cellularMode", "active"),
    ("--cellularBars", "4"),
    ("--batteryState", "charged"),
    ("--batteryLevel", "100"),
]
