//
//  BootSimulatorTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerBootSimulatorTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "boot_simulator",
        description: "Boot an iOS simulator by UDID. Falls back to session default simulator_udid. If 'name' is provided without 'udid', resolves the name to a UDID via simctl. Sets session simulator_udid on success.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "name": .init(
                    type: "string",
                    description: "Simulator name. Used to resolve UDID if udid is not provided."
                ),
            ]
        ),
        category: .simulator,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        do {
            var udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            }

            // Resolve name → UDID if name provided without explicit UDID
            if udid == nil, case .string(let name) = args["name"] {
                let listResult = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "list", "devices", "-j"],
                    timeout: 30,
                    environment: nil
                )
                guard listResult.succeeded, let data = listResult.stdout.data(using: .utf8) else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Failed to list devices for name resolution"
                    ))
                }
                let simulators = try parseSimctlDevices(data)
                let matches = simulators.filter { $0.name == name && $0.isAvailable }
                guard let match = matches.first else {
                    return .error(ToolError(
                        code: .invalidInput,
                        message: "No available simulator found with name '\(name)'"
                    ))
                }
                udid = match.udid
            }

            // Fall back to session default
            if udid == nil {
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

            return await concurrency.withLock(
                key: "simulator:\(resolvedUDID)",
                owner: "boot_simulator"
            ) {
                do {
                    let result = try await executor.execute(
                        executable: "/usr/bin/xcrun",
                        arguments: ["simctl", "boot", resolvedUDID],
                        timeout: 30,
                        environment: nil
                    )

                    guard result.succeeded else {
                        return .error(ToolError(
                            code: .commandFailed,
                            message: "simctl boot failed",
                            details: result.stderr
                        ))
                    }

                    await session.set(.simulatorUDID, value: resolvedUDID)

                    return .success(ToolResult(
                        content: "Simulator \(resolvedUDID) booted successfully.\nSession default set: simulator_udid = \(resolvedUDID)"
                    ))
                } catch let error as ToolError {
                    return .error(error)
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed to boot simulator: \(error.localizedDescription)"
                    ))
                }
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
}
