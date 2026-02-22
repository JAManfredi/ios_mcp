//
//  TypeTextTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerTypeTextTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil
) async {
    let manifest = ToolManifest(
        name: "type_text",
        description: "Type text into the iOS simulator. Types into the currently focused field by default, or targets a specific element via accessibility identifier, label, or coordinates. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "text": .init(
                    type: "string",
                    description: "The text to type (required)."
                ),
                "accessibility_id": .init(
                    type: "string",
                    description: "Accessibility identifier of the target element (optional)."
                ),
                "accessibility_label": .init(
                    type: "string",
                    description: "Accessibility label of the target element (optional)."
                ),
                "x": .init(
                    type: "number",
                    description: "X coordinate (used with y, optional)."
                ),
                "y": .init(
                    type: "number",
                    description: "Y coordinate (used with x, optional)."
                ),
            ],
            required: ["text"]
        ),
        category: .uiAutomation
    )

    await registry.register(manifest: manifest) { args in
        let resolvedAxe: String
        if let axePath {
            resolvedAxe = axePath
        } else {
            switch resolveAxePath() {
            case .success(let path): resolvedAxe = path
            case .failure(let error): return .error(error)
            }
        }

        guard case .string(let text) = args["text"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: text"
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

        var axeArgs = ["type", "--udid", resolvedUDID, "--text", text]

        // Targeting is optional for type_text — if omitted, types into focused field
        if case .success(let targetArgs) = resolveAxeTarget(from: args) {
            axeArgs += targetArgs
        }

        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: axeArgs,
                timeout: 120,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "axe type failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: "Typed text on simulator \(resolvedUDID)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to type text: \(error.localizedDescription)"
            ))
        }
    }
}
