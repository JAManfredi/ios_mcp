//
//  DeviceScreenshotTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerDeviceScreenshotTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "device_screenshot",
        description: "Capture a screenshot from a physical iOS device (requires Xcode 16+). Falls back to session default device_udid.",
        inputSchema: JSONSchema(
            properties: [
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
            ]
        ),
        category: .device,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        switch await resolveDeviceUDID(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let udid):
            let outputPath = NSTemporaryDirectory() + "ios-mcp-device-screenshot-\(UUID().uuidString).png"

            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["devicectl", "device", "screenshot", "--device", udid, "--output", outputPath],
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Device screenshot failed. This feature requires Xcode 16+.",
                        details: result.stderr
                    ))
                }

                if let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)) {
                    _ = try? await artifacts.store(
                        data: data,
                        filename: "device-screenshot.png",
                        mimeType: "image/png"
                    )
                }

                return .success(ToolResult(
                    content: "Device screenshot captured.\nDevice: \(udid)\nPath: \(outputPath)",
                    artifacts: [ArtifactReference(path: outputPath, mimeType: "image/png")]
                ))
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to capture device screenshot: \(error.localizedDescription)"
                ))
            }
        }
    }
}
