//
//  UninstallAppTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerUninstallAppTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "uninstall_app",
        description: "Uninstall an app from the iOS simulator. Removes the app bundle and its data. Use build_run_simulator to reinstall. Falls back to session defaults for simulator_udid and bundle_id.",
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
        category: .simulator,
        isDestructive: true
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

            let bundleID: String?
            if case .string(let b) = args["bundle_id"] {
                bundleID = b
            } else {
                bundleID = await session.get(.bundleID)
            }

            guard let resolvedBundleID = bundleID else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No bundle_id specified, and no session default is set. Run show_build_settings first."
                ))
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "uninstall", resolvedUDID, resolvedBundleID],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl uninstall failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Uninstalled \(resolvedBundleID) from simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to uninstall app: \(error.localizedDescription)"
            ))
        }
    }
}
