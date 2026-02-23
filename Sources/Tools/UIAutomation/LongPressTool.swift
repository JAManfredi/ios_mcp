//
//  LongPressTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerLongPressTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "long_press",
        description: "Long press a UI element in the iOS simulator by accessibility identifier, label, or coordinates. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "duration": .init(
                    type: "number",
                    description: "Press duration in seconds (optional, default ~1.0s)."
                ),
                "accessibility_id": .init(
                    type: "string",
                    description: "Accessibility identifier of the target element (preferred)."
                ),
                "accessibility_label": .init(
                    type: "string",
                    description: "Accessibility label of the target element."
                ),
                "x": .init(
                    type: "number",
                    description: "X coordinate (used with y when no accessibility target)."
                ),
                "y": .init(
                    type: "number",
                    description: "Y coordinate (used with x when no accessibility target)."
                ),
            ]
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

        let targetArgs: [String]
        switch resolveAxeTarget(from: args) {
        case .success(let t): targetArgs = t
        case .failure(let error): return .error(error)
        }

        var axeArgs = ["longpress", "--udid", resolvedUDID]

        if let duration = extractLongPressDuration(from: args["duration"]) {
            axeArgs += ["--duration", String(format: "%.1f", duration)]
        }

        axeArgs += targetArgs

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
                    message: "axe longpress failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: "Long pressed element on simulator \(resolvedUDID)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to long press: \(error.localizedDescription)"
            ))
        }
    }
}

private func extractLongPressDuration(from value: Value?) -> Double? {
    guard let value else { return nil }
    switch value {
    case .int(let i): return Double(i)
    case .double(let d): return d
    default: return nil
    }
}
