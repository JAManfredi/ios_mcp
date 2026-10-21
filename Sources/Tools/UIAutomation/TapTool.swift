//
//  TapTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerTapTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil,
    validator: DefaultsValidator,
    nativeUI: (any NativeUIAutomating)? = nil
) async {
    let manifest = ToolManifest(
        name: "tap",
        description: "Tap a UI element in the iOS simulator by accessibility identifier, label, or coordinates. Not all elements appear in the accessibility tree (e.g. UITabBar items). Use inspect_ui to inspect available elements, or fall back to coordinates. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
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

        if let nativeUI {
            do {
                let target = try nativeTapTarget(args)
                return .success(try await nativeUI.tap(udid: resolvedUDID, target: target))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(code: .commandFailed, message: "Native UI operation failed or was cancelled. Inspect the screen before retrying a tap."))
            }
        }

        let resolvedAxe: String
        if let axePath {
            resolvedAxe = axePath
        } else {
            switch resolveAxePath() {
            case .success(let path): resolvedAxe = path
            case .failure(let error): return .error(error)
            }
        }

        let targetArgs: [String]
        switch resolveAxeTarget(from: args) {
        case .success(let t): targetArgs = t
        case .failure(let error): return .error(error)
        }

        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: ["tap", "--udid", resolvedUDID] + targetArgs,
                timeout: 120,
                environment: nil
            )

            guard result.succeeded else {
                return .error(axeCommandError("axe tap failed", stderr: result.stderr))
            }

            return .success(ToolResult(content: "Tapped element on simulator \(resolvedUDID)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to tap element: \(error.localizedDescription)"
            ))
        }
    }
}

/// Mirror target precedence without AXe's integer coordinate conversion.
private func nativeTapTarget(_ args: [String: Value]) throws -> NativeUITarget {
    if case .string(let id) = args["accessibility_id"], !id.isEmpty { return .identifier(id) }
    if case .string(let label) = args["accessibility_label"], !label.isEmpty { return .label(label) }
    func number(_ value: Value?) -> Double? {
        switch value {
        case .int(let value): return Double(value)
        case .double(let value) where value.isFinite: return value
        default: return nil
        }
    }
    guard let x = number(args["x"]), let y = number(args["y"]), x >= 0, y >= 0 else {
        throw ToolError(code: .invalidInput, message: "No target: provide an accessibility identifier, label, or finite nonnegative x and y in screen points.")
    }
    return .coordinates(x: x, y: y)
}
