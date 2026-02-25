//
//  SendPushNotificationTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerSendPushNotificationTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "send_push_notification",
        description: "Send a push notification to an app on the iOS simulator. Provide title and body for a simple notification, or payload_json for a custom APS payload. The app must be installed on the simulator. Falls back to session defaults for simulator_udid and bundle_id.",
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
                "title": .init(
                    type: "string",
                    description: "Notification title."
                ),
                "body": .init(
                    type: "string",
                    description: "Notification body text."
                ),
                "badge": .init(
                    type: "number",
                    description: "Badge count (optional)."
                ),
                "sound": .init(
                    type: "string",
                    description: "Sound name (optional, e.g. 'default')."
                ),
                "payload_json": .init(
                    type: "string",
                    description: "Raw JSON payload string. Overrides title/body/badge/sound when provided."
                ),
            ]
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

            let payloadJSON: String
            if case .string(let raw) = args["payload_json"] {
                payloadJSON = raw
            } else {
                guard case .string(let title) = args["title"],
                      case .string(let body) = args["body"] else {
                    return .error(ToolError(
                        code: .invalidInput,
                        message: "Either payload_json or both title and body are required."
                    ))
                }

                var aps: [String: Any] = ["alert": ["title": title, "body": body]]

                if case .int(let badge) = args["badge"] {
                    aps["badge"] = badge
                } else if case .double(let badge) = args["badge"] {
                    aps["badge"] = Int(badge)
                }

                if case .string(let sound) = args["sound"] {
                    aps["sound"] = sound
                }

                let payload: [String: Any] = ["aps": aps]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                payloadJSON = String(data: data, encoding: .utf8)!
            }

            let tempDir = NSTemporaryDirectory()
            let tempFile = (tempDir as NSString).appendingPathComponent("ios-mcp-push-\(UUID().uuidString).json")

            try payloadJSON.write(toFile: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: tempFile) }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "push", resolvedUDID, resolvedBundleID, tempFile],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl push failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Push notification sent to \(resolvedBundleID) on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to send push notification: \(error.localizedDescription)"
            ))
        }
    }
}
