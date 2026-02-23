//
//  LaunchAppTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerLaunchAppTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "launch_app",
        description: "Launch an app on a running iOS simulator. Falls back to session defaults for udid and bundle_id. Optional launch arguments can be passed.",
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
                "args": .init(
                    type: "string",
                    description: "Space-separated launch arguments to pass to the app."
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

            var simctlArgs = ["simctl", "launch", udid, bundleID]
            if case .string(let launchArgs) = args["args"] {
                simctlArgs += launchArgs.components(separatedBy: " ").filter { !$0.isEmpty }
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: simctlArgs,
                timeout: 60,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl launch failed",
                    details: result.stderr
                ))
            }

            let pid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            var content = "Launched \(bundleID) on simulator \(udid)."
            if !pid.isEmpty {
                content += "\nPID: \(pid)"
            }

            return .success(ToolResult(content: content))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to launch app: \(error.localizedDescription)"
            ))
        }
    }
}
