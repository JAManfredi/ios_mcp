//
//  StartRecordingTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerStartRecordingTool(
    with registry: ToolRegistry,
    session: SessionStore,
    videoRecording: any VideoRecording,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "start_recording",
        description: "Start recording video from an iOS simulator screen. Returns a session ID for later retrieval with stop_recording. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        let udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        } else {
            udid = await session.get(.simulatorUDID)
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

        do {
            let sessionID = try await videoRecording.startRecording(udid: udid)

            let lines = [
                "Video recording started.",
                "Session ID: \(sessionID)",
                "Simulator: \(udid)",
                "\nUse stop_recording with this session_id to stop recording and retrieve the video.",
            ]

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to start video recording: \(error.localizedDescription)"
            ))
        }
    }
}
