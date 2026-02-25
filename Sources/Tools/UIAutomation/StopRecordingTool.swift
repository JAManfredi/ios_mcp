//
//  StopRecordingTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStopRecordingTool(
    with registry: ToolRegistry,
    videoRecording: any VideoRecording,
    artifacts: ArtifactStore
) async {
    let manifest = ToolManifest(
        name: "stop_recording",
        description: "Stop a running video recording session and retrieve the recorded video file. Requires the session_id from start_recording.",
        inputSchema: JSONSchema(
            properties: [
                "session_id": .init(
                    type: "string",
                    description: "Session ID returned by start_recording."
                ),
            ],
            required: ["session_id"]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let sessionID) = args["session_id"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "session_id is required."
            ))
        }

        do {
            let result = try await videoRecording.stopRecording(sessionID: sessionID)

            // Store the video data in the artifact store for lifecycle management
            if let videoData = try? Data(contentsOf: URL(fileURLWithPath: result.path)) {
                _ = try? await artifacts.store(
                    data: videoData,
                    filename: "recording-\(sessionID).mp4",
                    mimeType: "video/mp4"
                )
            }

            let lines = [
                "Video recording stopped.",
                "File path: \(result.path)",
                "File size: \(formatBytes(result.fileSize))",
            ]

            return .success(ToolResult(
                content: lines.joined(separator: "\n"),
                artifacts: [ArtifactReference(path: result.path, mimeType: "video/mp4")]
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to stop video recording: \(error.localizedDescription)"
            ))
        }
    }
}

private func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024.0
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024.0
    return String(format: "%.1f MB", mb)
}
