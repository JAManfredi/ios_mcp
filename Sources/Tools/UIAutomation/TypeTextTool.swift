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
    axePath: String? = nil,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "type_text",
        description: "Type text into the iOS simulator. Sends keyboard events to the currently focused text field by default, or targets a specific element via accessibility identifier, label, or coordinates. For custom keypads or non-standard input views, use tap on individual buttons instead. Falls back to session default simulator_udid.",
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

        if let error = await validator.validateSimulatorUDID(resolvedUDID) {
            return .error(error)
        }

        // If targeting is provided, tap the element first to focus it
        if case .success(let targetArgs) = resolveAxeTarget(from: args) {
            do {
                let tapResult = try await executor.execute(
                    executable: resolvedAxe,
                    arguments: ["tap", "--udid", resolvedUDID] + targetArgs,
                    timeout: 120,
                    environment: nil
                )
                guard tapResult.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "Failed to tap target element before typing",
                        details: tapResult.stderr
                    ))
                }
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to tap target element: \(error.localizedDescription)"
                ))
            }
        }

        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: ["type", text, "--udid", resolvedUDID],
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
