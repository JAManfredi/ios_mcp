//
//  ScreenshotTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerScreenshotTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "screenshot",
        description: "Capture a screenshot of the iOS simulator screen. Returns the image as an MCP image content block. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "inline": .init(
                    type: "boolean",
                    description: "When false, returns only the artifact path without inlining base64 image data. Defaults to true."
                ),
            ]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        var udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        }

        var inlineImage = true
        if case .bool(let b) = args["inline"] {
            inlineImage = b
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

        let tempPath = NSTemporaryDirectory() + "ios-mcp-screenshot-\(UUID().uuidString).png"

        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "io", resolvedUDID, "screenshot", tempPath],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl screenshot failed",
                    details: result.stderr
                ))
            }

            let fileURL = URL(fileURLWithPath: tempPath)
            let data = try Data(contentsOf: fileURL)
            try? FileManager.default.removeItem(at: fileURL)

            guard data.count > 0 else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "Screenshot file is empty or corrupt"
                ))
            }

            let ref = try await artifacts.store(
                data: data,
                filename: "screenshot.png",
                mimeType: "image/png"
            )

            return .success(ToolResult(
                content: "Screenshot captured for simulator \(resolvedUDID).\nStored at: \(ref.path)",
                artifacts: [ref],
                inlineArtifacts: inlineImage
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to capture screenshot: \(error.localizedDescription)"
            ))
        }
    }
}
