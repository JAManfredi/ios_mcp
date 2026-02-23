//
//  EraseSimulatorTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerEraseSimulatorTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "erase_simulator",
        description: "Erase all content and settings from an iOS simulator by UDID. The simulator must be shut down first. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "confirm": .init(
                    type: "boolean",
                    description: "Must be true to execute. Omit to preview what will happen."
                ),
            ]
        ),
        category: .simulator,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        let confirmed: Bool
        if case .bool(let c) = args["confirm"] {
            confirmed = c
        } else {
            confirmed = false
        }

        guard confirmed else {
            return .error(ToolError(
                code: .invalidInput,
                message: "erase_simulator is destructive: it erases all content and settings from the simulator. Pass confirm: true to proceed."
            ))
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

        return await concurrency.withLock(
            key: "simulator:\(resolvedUDID)",
            owner: "erase_simulator"
        ) {
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "erase", resolvedUDID],
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl erase failed",
                        details: result.stderr
                    ))
                }

                return .success(ToolResult(
                    content: "Simulator \(resolvedUDID) erased successfully."
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to erase simulator: \(error.localizedDescription)"
                ))
            }
        }
    }
}
