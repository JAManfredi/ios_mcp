//
//  ClearLocationTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerClearLocationTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "clear_location",
        description: "Clear a simulated GPS location on an iOS simulator, reverting to no location. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
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

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "location", resolvedUDID, "clear"],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl location clear failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Simulated location cleared on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to clear location: \(error.localizedDescription)"
            ))
        }
    }
}
