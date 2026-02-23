//
//  WriteUserDefaultTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerWriteUserDefaultTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "write_user_default",
        description: "Write a user default value for an app on the iOS simulator. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "domain": .init(
                    type: "string",
                    description: "App bundle ID (e.g. com.example.MyApp)."
                ),
                "key": .init(
                    type: "string",
                    description: "The defaults key to write."
                ),
                "value": .init(
                    type: "string",
                    description: "The value to write."
                ),
                "type": .init(
                    type: "string",
                    description: "Value type: string, int, float, or bool. Defaults to string.",
                    enumValues: ["string", "int", "float", "bool"]
                ),
            ],
            required: ["domain", "key", "value"]
        ),
        category: .inspection,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        // 1. Validate required parameters
        guard case .string(let domain) = args["domain"], !domain.isEmpty else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: domain (app bundle ID)."
            ))
        }
        guard case .string(let key) = args["key"], !key.isEmpty else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: key."
            ))
        }
        guard case .string(let value) = args["value"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: value."
            ))
        }

        // 2. Resolve type flag
        let validTypes = ["string", "int", "float", "bool"]
        var typeFlag = "string"
        if case .string(let t) = args["type"], !t.isEmpty {
            guard validTypes.contains(t) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "Invalid type '\(t)'. Must be one of: \(validTypes.joined(separator: ", "))."
                ))
            }
            typeFlag = t
        }

        // 3. Resolve UDID
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

        // 4. Build command and execute
        let arguments = [
            "simctl", "spawn", resolvedUDID,
            "defaults", "write", domain, key,
            "-\(typeFlag)", value,
        ]

        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: arguments,
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "defaults write failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Wrote \(key) = \(value) (-\(typeFlag)) to \(domain) on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to write user default: \(error.localizedDescription)"
            ))
        }
    }
}
