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
        description: "Capture a screenshot from a physical iOS device via `devicectl device capture screenshot` (requires Xcode 26.6+). Falls back to session default device_udid.",
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

            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: deviceCaptureScreenshotArgs(udid: udid, destination: outputPath),
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Device screenshot failed. `devicectl device capture screenshot` requires Xcode 26.6 or later.",
                        details: result.stderr
                    ))
                }

                let fileURL = URL(fileURLWithPath: outputPath)
                guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "devicectl reported success but wrote no screenshot to \(outputPath)."
                    ))
                }

                let ref = try await artifacts.store(
                    data: data,
                    filename: "device-screenshot.png",
                    mimeType: "image/png"
                )

                return .success(ToolResult(
                    content: "Device screenshot captured.\nDevice: \(udid)\nStored at: \(ref.path)",
                    artifacts: [ref]
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to capture device screenshot: \(error.localizedDescription)"
                ))
            }
        }
    }
}

/// `devicectl device capture screenshot` (Xcode 26.6+). There was never a
/// `devicectl device screenshot` subcommand; `capture` is the only path, and it
/// writes to `--destination`, not `--output`.
func deviceCaptureScreenshotArgs(udid: String, destination: String) -> [String] {
    ["devicectl", "device", "capture", "screenshot", "--device", udid, "--destination", destination]
}
