//
//  ShutdownSimulatorTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerShutdownSimulatorTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy
) async {
    let manifest = ToolManifest(
        name: "shutdown_simulator",
        description: "Shut down a running iOS simulator by UDID. Falls back to session default simulator_udid. Keeps the session default so subsequent boot re-targets the same device.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ]
        ),
        category: .simulator,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        let udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        } else {
            udid = await session.get(.simulatorUDID)
        }

        guard let resolvedUDID = udid else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No simulator UDID provided, and no session default is set. Run list_simulators first."
            ))
        }

        return await concurrency.withLock(
            key: "simulator:\(resolvedUDID)",
            owner: "shutdown_simulator"
        ) {
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "shutdown", resolvedUDID],
                    timeout: 30,
                    environment: nil
                )

                guard result.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl shutdown failed",
                        details: result.stderr
                    ))
                }

                return .success(ToolResult(
                    content: "Simulator \(resolvedUDID) shut down successfully."
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to shut down simulator: \(error.localizedDescription)"
                ))
            }
        }
    }
}
