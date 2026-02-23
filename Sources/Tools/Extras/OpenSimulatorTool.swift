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
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "open_simulator",
        description: "Open the iOS Simulator app. Optionally boots a specific simulator by UDID first. Falls back to session default simulator_udid.",
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

        // Open Simulator.app
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/open",
                arguments: ["-a", "Simulator"],
                timeout: 15,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "Failed to open Simulator.app",
                    details: result.stderr
                ))
            }

            if let udid {
                return .success(ToolResult(
                    content: "Booted simulator \(udid) and opened Simulator.app."
                ))
            } else {
                return .success(ToolResult(
                    content: "Opened Simulator.app."
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
