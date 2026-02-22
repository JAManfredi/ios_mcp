//
//  ReadUserDefaultsTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerReadUserDefaultsTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "read_user_defaults",
        description: "Read user defaults for an app on the iOS simulator. Reads a specific key or all keys for the given domain (bundle ID). Falls back to session default simulator_udid.",
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
                    description: "Specific key to read. Reads all keys if omitted."
                ),
            ],
            required: ["domain"]
        ),
        category: .inspection
    )

    await registry.register(manifest: manifest) { args in
        // 1. Extract domain (required)
        guard case .string(let domain) = args["domain"], !domain.isEmpty else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: domain (app bundle ID)."
            ))
        }

        // 2. Resolve UDID
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

        // 3. Build command arguments
        var arguments = ["simctl", "spawn", resolvedUDID, "defaults", "read", domain]
        if case .string(let key) = args["key"], !key.isEmpty {
            arguments.append(key)
        }

        // 4. Execute
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
                    message: "defaults read failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: result.stdout))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to read user defaults: \(error.localizedDescription)"
            ))
        }
    }
}
