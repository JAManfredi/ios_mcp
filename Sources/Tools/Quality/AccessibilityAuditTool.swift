//
//  AccessibilityAuditTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerAccessibilityAuditTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    axePath: String? = nil
) async {
    let manifest = ToolManifest(
        name: "accessibility_audit",
        description: "Run an accessibility audit on the iOS simulator's current screen. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .quality
    )

    await registry.register(manifest: manifest) { args in
        // 1. Resolve axe path
        let resolvedAxe: String
        if let axePath {
            resolvedAxe = axePath
        } else {
            switch resolveAxePath() {
            case .success(let path): resolvedAxe = path
            case .failure(let error): return .error(error)
            }
        }

        // 2. Resolve UDID
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

        // 3. Try audit subcommand first, fall back to dump if not supported
        do {
            let result = try await executor.execute(
                executable: resolvedAxe,
                arguments: ["audit", "--udid", resolvedUDID],
                timeout: 120,
                environment: nil
            )

            if result.succeeded {
                return .success(ToolResult(content: result.stdout))
            }

            // If audit subcommand is not supported, fall back to dump
            if result.stderr.contains("unknown command") || result.stderr.contains("not recognized") {
                let dumpResult = try await executor.execute(
                    executable: resolvedAxe,
                    arguments: ["dump", "--udid", resolvedUDID],
                    timeout: 120,
                    environment: nil
                )

                guard dumpResult.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "axe dump failed",
                        details: dumpResult.stderr
                    ))
                }

                return .success(ToolResult(content: dumpResult.stdout))
            }

            return .error(ToolError(
                code: .commandFailed,
                message: "axe audit failed",
                details: result.stderr
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to run accessibility audit: \(error.localizedDescription)"
            ))
        }
    }
}
