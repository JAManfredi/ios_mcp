//
//  BuildDeviceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerBuildDeviceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator,
    progressReporter: ProgressReporter? = nil
) async {
    let manifest = ToolManifest(
        name: "build_device",
        description: "Build an Xcode project for a physical iOS device. Falls back to session defaults for workspace, project, scheme, configuration, device_udid, and derived_data_path. Code signing must be configured in the project.",
        inputSchema: JSONSchema(
            properties: [
                "workspace": .init(type: "string", description: "Path to .xcworkspace. Falls back to session default."),
                "project": .init(type: "string", description: "Path to .xcodeproj. Falls back to session default. Ignored if workspace is provided."),
                "scheme": .init(type: "string", description: "Scheme name. Falls back to session default."),
                "configuration": .init(type: "string", description: "Build configuration (e.g., Debug, Release). Falls back to session default, then Debug."),
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
                "derived_data_path": .init(type: "string", description: "Custom DerivedData path. Falls back to session default."),
                "extra_args": .init(type: "string", description: "Additional xcodebuild arguments, space-separated."),
            ]
        ),
        category: .device
    )

    await registry.register(manifest: manifest) { args in
        switch await resolveDeviceUDID(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let udid):
            let workspace: String?
            if case .string(let ws) = args["workspace"] {
                workspace = ws
            } else {
                workspace = await session.get(.workspace)
            }

            let project: String?
            if case .string(let proj) = args["project"] {
                project = proj
            } else {
                project = await session.get(.project)
            }

            let scheme: String?
            if case .string(let s) = args["scheme"] {
                scheme = s
            } else {
                scheme = await session.get(.scheme)
            }

            guard workspace != nil || project != nil else {
                return .error(ToolError(code: .invalidInput, message: "No workspace or project specified. Run discover_projects first."))
            }
            guard let scheme else {
                return .error(ToolError(code: .invalidInput, message: "No scheme specified. Run list_schemes first."))
            }

            let configuration: String
            if case .string(let config) = args["configuration"] {
                configuration = config
            } else {
                configuration = await session.get(.configuration) ?? "Debug"
            }

            let lockKey = "build:\(workspace ?? project ?? "unknown")"
            return await concurrency.withLock(key: lockKey, owner: "build_device") {
                var xcodebuildArgs = [String]()
                if let workspace {
                    xcodebuildArgs += ["-workspace", workspace]
                } else if let project {
                    xcodebuildArgs += ["-project", project]
                }
                xcodebuildArgs += ["-scheme", scheme, "-configuration", configuration]
                xcodebuildArgs += ["-destination", deviceDestination(udid: udid)]

                if case .string(let ddp) = args["derived_data_path"] {
                    xcodebuildArgs += ["-derivedDataPath", ddp]
                } else if let ddp = await session.get(.derivedDataPath) {
                    xcodebuildArgs += ["-derivedDataPath", ddp]
                }

                if case .string(let extra) = args["extra_args"] {
                    xcodebuildArgs += extra.components(separatedBy: " ").filter { !$0.isEmpty }
                }

                xcodebuildArgs.append("build")

                do {
                    let result = try await executor.execute(
                        executable: "/usr/bin/xcodebuild",
                        arguments: xcodebuildArgs,
                        timeout: 600,
                        environment: nil
                    )

                    if result.succeeded {
                        var lines = [
                            "Device build succeeded.",
                            "Scheme: \(scheme)",
                            "Configuration: \(configuration)",
                            "Device: \(udid)",
                        ]
                        if !result.stderr.isEmpty {
                            let warnings = result.stderr.components(separatedBy: .newlines)
                                .filter { $0.contains("warning:") }
                            if !warnings.isEmpty {
                                lines.append("Warnings: \(warnings.count)")
                            }
                        }
                        return .success(ToolResult(content: lines.joined(separator: "\n")))
                    } else {
                        return .error(ToolError(
                            code: .commandFailed,
                            message: "Device build failed for scheme '\(scheme)'.",
                            details: result.stderr
                        ))
                    }
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed to run xcodebuild: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
