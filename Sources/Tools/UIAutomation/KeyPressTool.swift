//
//  KeyPressTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerKeyPressTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "key_press",
        description: "Send a key press to the iOS simulator (e.g. return, escape, delete). The key is sent to the currently focused responder. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "key": .init(
                    type: "string",
                    description: "The key to press (required). Examples: return, escape, delete, tab."
                ),
            ],
            required: ["key"]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        let resolvedAxe: String
        if let axePath {
            resolvedAxe = axePath
        } else {
            switch resolveAxePath() {
            case .success(let path): resolvedAxe = path
            case .failure(let error): return .error(error)
            }
        }

        guard case .string(let key) = args["key"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: key"
            ))
        }

        var udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        }
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

        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: ["key", "--udid", resolvedUDID, "--key", key],
                timeout: 120,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "axe key failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: "Pressed key '\(key)' on simulator \(resolvedUDID)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to press key: \(error.localizedDescription)"
            ))
        }
    }
}
