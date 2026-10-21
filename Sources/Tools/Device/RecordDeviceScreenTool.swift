//
//  RecordDeviceScreenTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

/// Upper bound on one recording, so a call can't hold the device indefinitely.
let maxDeviceRecordingSeconds = 120

func registerRecordDeviceScreenTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "record_device_screen",
        description: "Record a physical iOS device's screen for a fixed duration via `devicectl device capture screen-record` (Xcode 26.6+) and return the video. Start the interaction you want to capture right after calling, or drive it with launch_app_device. Falls back to session default device_udid.",
        inputSchema: JSONSchema(
            properties: [
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
                "duration": .init(
                    type: "integer",
                    description: "Whole seconds to record (1–\(maxDeviceRecordingSeconds)). Default: 10."
                ),
            ]
        ),
        category: .device,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        let duration: Int
        if let value = args["duration"] {
            switch integerArgument(value, named: "duration") {
            case .success(let integer): duration = integer
            case .failure(let error): return .error(error)
            }
        } else {
            duration = 10
        }
        guard (1...maxDeviceRecordingSeconds).contains(duration) else {
            return .error(ToolError(
                code: .invalidInput,
                message: "duration must be between 1 and \(maxDeviceRecordingSeconds) seconds."
            ))
        }

        let udid: String
        switch await resolveDeviceUDID(from: args, session: session, validator: validator) {
        case .success(let resolved): udid = resolved
        case .failure(let error): return .error(error)
        }

        return await concurrency.withLock(key: "device-recording:\(udid)", owner: "record_device_screen") {
            let outputPath = NSTemporaryDirectory() + "ios-mcp-device-recording-\(UUID().uuidString).mp4"
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: deviceScreenRecordArgs(udid: udid, destination: outputPath, duration: duration),
                    timeout: TimeInterval(duration + 60),
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Device screen recording failed. `devicectl device capture screen-record` requires Xcode 26.6 or later and an unlocked device.",
                        details: result.stderr
                    ))
                }

                let fileURL = URL(fileURLWithPath: outputPath)
                guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "devicectl reported success but wrote no video to \(outputPath)."
                    ))
                }
                try? FileManager.default.removeItem(at: fileURL)

                let ref = try await artifacts.store(data: data, filename: "device-recording.mp4", mimeType: "video/mp4")
                let megabytes = String(format: "%.1f", Double(data.count) / 1_048_576)
                return .success(ToolResult(
                    content: "Recorded \(duration)s from device \(udid) (\(megabytes) MB).\nStored at: \(ref.path)",
                    artifacts: [ref]
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to record device screen: \(error.localizedDescription)"
                ))
            }
        }
    }
}

func deviceScreenRecordArgs(udid: String, destination: String, duration: Int) -> [String] {
    ["devicectl", "device", "capture", "screen-record",
     "--device", udid, "--destination", destination, "--duration", String(duration)]
}
