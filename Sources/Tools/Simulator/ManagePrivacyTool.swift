//
//  ManagePrivacyTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerManagePrivacyTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let validActions: Set<String> = ["grant", "revoke", "reset"]
    let validServices: Set<String> = [
        "all", "calendar", "camera", "contacts",
        "location", "microphone", "photos", "reminders",
    ]

    let manifest = ToolManifest(
        name: "manage_privacy",
        description: "Grant, revoke, or reset privacy permissions for an app on the iOS simulator. Avoids permission dialogs during automated testing. bundle_id is required except for 'reset all' which resets all apps. Falls back to session defaults for simulator_udid and bundle_id.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "action": .init(
                    type: "string",
                    description: "Privacy action to perform.",
                    enumValues: ["grant", "revoke", "reset"]
                ),
                "service": .init(
                    type: "string",
                    description: "Privacy service to manage.",
                    enumValues: Array(validServices).sorted()
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "App bundle identifier. Falls back to session default. Not required for 'reset all'."
                ),
            ],
            required: ["action", "service"]
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

            guard case .string(let action) = args["action"], validActions.contains(action) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "action is required and must be one of: \(validActions.sorted().joined(separator: ", "))"
                ))
            }

            guard case .string(let service) = args["service"], validServices.contains(service) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "service is required and must be one of: \(validServices.sorted().joined(separator: ", "))"
                ))
            }

            let bundleID: String?
            if case .string(let b) = args["bundle_id"] {
                bundleID = b
            } else {
                bundleID = await session.get(.bundleID)
            }

            // bundle_id is not required for "reset all"
            let needsBundleID = !(action == "reset" && service == "all")
            if needsBundleID {
                guard let bundleID else {
                    return .error(ToolError(
                        code: .invalidInput,
                        message: "No bundle_id specified, and no session default is set. Run show_build_settings first."
                    ))
                }

                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "privacy", resolvedUDID, action, service, bundleID],
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl privacy failed",
                        details: result.stderr
                    ))
                }

                return .success(ToolResult(
                    content: "Privacy \(action) \(service) for \(bundleID) on simulator \(resolvedUDID)."
                ))
            }

            var privacyArgs = ["simctl", "privacy", resolvedUDID, action, service]
            if let bundleID {
                privacyArgs.append(bundleID)
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: privacyArgs,
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl privacy failed",
                    details: result.stderr
                ))
            }

            let target = bundleID ?? "all apps"
            return .success(ToolResult(
                content: "Privacy \(action) \(service) for \(target) on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to manage privacy: \(error.localizedDescription)"
            ))
        }
    }
}
