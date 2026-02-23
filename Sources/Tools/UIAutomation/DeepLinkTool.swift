//
//  DeepLinkTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerDeepLinkTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "deep_link",
        description: "Open a URL (deep link or universal link) in the iOS simulator. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "url": .init(
                    type: "string",
                    description: "The URL to open in the simulator (required)."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ],
            required: ["url"]
        ),
        category: .uiAutomation,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let url) = args["url"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: url"
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
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "openurl", resolvedUDID, url],
                timeout: 60,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl openurl failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Opened URL '\(url)' on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to open URL: \(error.localizedDescription)"
            ))
        }
    }
}
