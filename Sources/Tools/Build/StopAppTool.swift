//
//  StopAppTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStopAppTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "stop_app",
        description: "Stop a running app on an iOS simulator. Falls back to session defaults for udid and bundle_id.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "App bundle identifier. Falls back to session default."
                ),
            ]
        ),
        category: .build
    )

    await registry.register(manifest: manifest) { args in
        do {
            let udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            } else {
                udid = await session.get(.simulatorUDID)
            }

            let bundleID: String?
            if case .string(let b) = args["bundle_id"] {
                bundleID = b
            } else {
                bundleID = await session.get(.bundleID)
            }

            guard let udid else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No simulator UDID specified, and no session default is set. Run list_simulators first."
                ))
            }

            if let error = await validator.validateSimulatorUDID(udid) {
                return .error(error)
            }

            guard let bundleID else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No bundle_id specified, and no session default is set. Run show_build_settings first."
                ))
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "terminate", udid, bundleID],
                timeout: 60,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl terminate failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Stopped \(bundleID) on simulator \(udid)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to stop app: \(error.localizedDescription)"
            ))
        }
    }
}
