//
//  OpenSimulatorTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerOpenSimulatorTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "open_simulator",
        description: "Open the simulator viewer (Device Hub on Xcode 27+, Simulator.app on earlier Xcode). Optionally boots a specific simulator by UDID first. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID to boot before opening. Falls back to session default."
                ),
            ]
        ),
        category: .extras,
        isDestructive: false
    )

    await registry.register(manifest: manifest) { args in
        let udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        } else {
            udid = await session.get(.simulatorUDID)
        }

        // Validate UDID if provided
        if let udid {
            if let error = await validator.validateSimulatorUDID(udid) {
                return .error(error)
            }
        }

        // Boot the simulator if a UDID is available
        if let udid {
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "boot", udid],
                    timeout: 30,
                    environment: nil
                )

                // Ignore "already booted" errors (exit 149 with "Booted" in stderr)
                if !result.succeeded && !result.stderr.contains("Booted") {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Failed to boot simulator \(udid)",
                        details: result.stderr
                    ))
                }
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to boot simulator: \(error.localizedDescription)"
                ))
            }
        }

        // Xcode 27 replaced Simulator.app with Device Hub. Open by bundle ID,
        // newest first, so older Xcode installs keep working.
        do {
            var failures: [String] = []
            var openedApp: SimulatorViewerApp?
            for app in SimulatorViewerApp.allCases {
                let result = try await executor.execute(
                    executable: "/usr/bin/open",
                    arguments: ["-b", app.bundleID],
                    timeout: 15,
                    environment: nil
                )
                if result.succeeded {
                    openedApp = app
                    break
                }
                failures.append("\(app.displayName): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            guard let openedApp else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "Failed to open Device Hub or Simulator.app",
                    details: failures.joined(separator: "\n")
                ))
            }

            if let udid {
                return .success(ToolResult(
                    content: "Booted simulator \(udid) and opened \(openedApp.displayName)."
                ))
            } else {
                return .success(ToolResult(
                    content: "Opened \(openedApp.displayName)."
                ))
            }
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to open Simulator: \(error.localizedDescription)"
            ))
        }
    }
}

/// The GUI that displays simulators. Ordered newest first.
enum SimulatorViewerApp: CaseIterable {
    /// Xcode 27+: Device Hub replaced Simulator.app.
    case deviceHub
    /// Xcode 26 and earlier.
    case simulator

    var bundleID: String {
        switch self {
        case .deviceHub: "com.apple.dt.Devices"
        case .simulator: "com.apple.iphonesimulator"
        }
    }

    var displayName: String {
        switch self {
        case .deviceHub: "Device Hub"
        case .simulator: "Simulator.app"
        }
    }
}
