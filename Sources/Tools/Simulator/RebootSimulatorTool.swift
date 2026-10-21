//
//  RebootSimulatorTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerRebootSimulatorTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "reboot_simulator",
        description: "Reboot a booted simulator in one step with `simctl reboot` (Xcode 27+). Faster than shutdown_simulator + boot_simulator, and keeps installed apps and data. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .simulator,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        let resolvedUDID: String
        switch await resolveSimulatorUDID(from: args, session: session, validator: validator) {
        case .success(let udid): resolvedUDID = udid
        case .failure(let error): return .error(error)
        }

        return await concurrency.withLock(
            key: "simulator:\(resolvedUDID)",
            owner: "reboot_simulator"
        ) {
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "reboot", resolvedUDID],
                    timeout: 180,
                    environment: nil
                )

                guard result.succeeded else {
                    let unknownCommand = result.stderr.contains("Unknown subcommand")
                        || result.stderr.contains("unrecognized subcommand")
                    return .error(ToolError(
                        code: unknownCommand ? .dependencyMissing : .commandFailed,
                        message: unknownCommand
                            ? "simctl reboot needs Xcode 27 or later. Use shutdown_simulator then boot_simulator instead."
                            : "simctl reboot failed",
                        details: result.stderr
                    ))
                }

                return .success(ToolResult(
                    content: "Simulator \(resolvedUDID) rebooted."
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to reboot simulator: \(error.localizedDescription)"
                ))
            }
        }
    }
}
