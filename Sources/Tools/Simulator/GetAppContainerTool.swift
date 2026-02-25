//
//  GetAppContainerTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerGetAppContainerTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let validContainers: Set<String> = ["app", "data", "groups"]

    let manifest = ToolManifest(
        name: "get_app_container",
        description: "Get the filesystem path to an app's container on the iOS simulator. Returns the absolute path for the app bundle, data directory, or shared group containers. Defaults to 'data' container. Falls back to session defaults for simulator_udid and bundle_id.",
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
                "container": .init(
                    type: "string",
                    description: "Container type: 'app', 'data', or 'groups'. Defaults to 'data'.",
                    enumValues: ["app", "data", "groups"]
                ),
            ]
        ),
        category: .simulator,
        isReadOnly: true
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

            let container: String
            if case .string(let c) = args["container"] {
                guard validContainers.contains(c) else {
                    return .error(ToolError(
                        code: .invalidInput,
                        message: "container must be one of: app, data, groups"
                    ))
                }
                container = c
            } else {
                container = "data"
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "get_app_container", resolvedUDID, resolvedBundleID, container],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl get_app_container failed",
                    details: result.stderr
                ))
            }

            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(ToolResult(
                content: "Container path (\(container)): \(path)"
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to get app container: \(error.localizedDescription)"
            ))
        }
    }
}
