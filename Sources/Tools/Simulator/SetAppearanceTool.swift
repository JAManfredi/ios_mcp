//
//  SetAppearanceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerSetAppearanceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "set_appearance",
        description: "Set the simulator appearance to light or dark mode. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "appearance": .init(
                    type: "string",
                    description: "Appearance mode: 'light' or 'dark'.",
                    enumValues: ["light", "dark"]
                ),
            ],
            required: ["appearance"]
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

            guard case .string(let appearance) = args["appearance"],
                  appearance == "light" || appearance == "dark" else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "appearance is required and must be 'light' or 'dark'."
                ))
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "ui", resolvedUDID, "appearance", appearance],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl ui appearance failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Appearance set to \(appearance) on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to set appearance: \(error.localizedDescription)"
            ))
        }
    }
}
