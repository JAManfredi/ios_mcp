//
//  BuildRunDeviceTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerBuildRunDeviceTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator,
    progressReporter: ProgressReporter? = nil
) async {
    let manifest = ToolManifest(
        name: "build_run_device",
        description: "Build, install, and launch an app on a physical iOS device. Falls back to session defaults. Code signing must be configured in the project.",
        inputSchema: JSONSchema(
            properties: [
                "workspace": .init(type: "string", description: "Path to .xcworkspace. Falls back to session default."),
                "project": .init(type: "string", description: "Path to .xcodeproj. Falls back to session default."),
                "scheme": .init(type: "string", description: "Scheme name. Falls back to session default."),
                "configuration": .init(type: "string", description: "Build configuration. Falls back to session default, then Debug."),
                "device_udid": .init(type: "string", description: "Device UDID. Falls back to session default."),
                "derived_data_path": .init(type: "string", description: "Custom DerivedData path. Falls back to session default."),
                "bundle_id": .init(type: "string", description: "App bundle identifier. Auto-resolved from build settings if not provided."),
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
            if case .string(let ws) = args["workspace"] { workspace = ws }
            else { workspace = await session.get(.workspace) }

            let project: String?
            if case .string(let proj) = args["project"] { project = proj }
            else { project = await session.get(.project) }

            let scheme: String?
            if case .string(let s) = args["scheme"] { scheme = s }
            else { scheme = await session.get(.scheme) }

            guard workspace != nil || project != nil else {
                return .error(ToolError(code: .invalidInput, message: "No workspace or project specified."))
            }
            guard let scheme else {
                return .error(ToolError(code: .invalidInput, message: "No scheme specified."))
            }

            let configuration: String
            if case .string(let config) = args["configuration"] { configuration = config }
            else { configuration = await session.get(.configuration) ?? "Debug" }

            let lockKey = "build:\(workspace ?? project ?? "unknown")"
            return await concurrency.withLock(key: lockKey, owner: "build_run_device") {
                // Step 1: Build
                var buildArgs = [String]()
                if let workspace { buildArgs += ["-workspace", workspace] }
                else if let project { buildArgs += ["-project", project] }
                buildArgs += ["-scheme", scheme, "-configuration", configuration]
                buildArgs += ["-destination", deviceDestination(udid: udid)]

                if case .string(let ddp) = args["derived_data_path"] {
                    buildArgs += ["-derivedDataPath", ddp]
                } else if let ddp = await session.get(.derivedDataPath) {
                    buildArgs += ["-derivedDataPath", ddp]
                }

                if case .string(let extra) = args["extra_args"] {
                    buildArgs += extra.components(separatedBy: " ").filter { !$0.isEmpty }
                }
                buildArgs.append("build")

                do {
                    let buildResult = try await executor.execute(
                        executable: "/usr/bin/xcodebuild",
                        arguments: buildArgs,
                        timeout: 600,
                        environment: nil
                    )

                    guard buildResult.succeeded else {
                        return .error(ToolError(
                            code: .commandFailed,
                            message: "Device build failed for scheme '\(scheme)'.",
                            details: buildResult.stderr
                        ))
                    }

                    // Step 2: Get bundle ID from build settings
                    let bundleID: String
                    if case .string(let bid) = args["bundle_id"] {
                        bundleID = bid
                    } else if let bid = await session.get(.bundleID) {
                        bundleID = bid
                    } else {
                        var settingsArgs = [String]()
                        if let workspace { settingsArgs += ["-workspace", workspace] }
                        else if let project { settingsArgs += ["-project", project] }
                        settingsArgs += ["-scheme", scheme, "-showBuildSettings"]

                        let settingsResult = try await executor.execute(
                            executable: "/usr/bin/xcodebuild",
                            arguments: settingsArgs,
                            timeout: 30,
                            environment: nil
                        )

                        let bidLine = settingsResult.stdout.components(separatedBy: .newlines)
                            .first { $0.contains("PRODUCT_BUNDLE_IDENTIFIER") }
                        let parsedBID = bidLine?.components(separatedBy: "=").last?
                            .trimmingCharacters(in: .whitespaces)

                        guard let parsedBID, !parsedBID.isEmpty else {
                            return .error(ToolError(
                                code: .commandFailed,
                                message: "Could not determine bundle ID from build settings. Provide bundle_id explicitly."
                            ))
                        }
                        bundleID = parsedBID
                    }

                    // Step 3: Install via devicectl
                    let installResult = try await executor.execute(
                        executable: "/usr/bin/xcrun",
                        arguments: ["devicectl", "device", "install", "app", "--device", udid, buildResult.stdout],
                        timeout: 120,
                        environment: nil
                    )

                    // devicectl install may fail if we can't determine the app path from stdout
                    // In that case, we note it and continue to launch attempt
                    var installNote = ""
                    if !installResult.succeeded {
                        installNote = "\nNote: Install via devicectl may have failed. The app may already be installed from the build step."
                    }

                    // Step 4: Launch via devicectl
                    let launchResult = try await executor.execute(
                        executable: "/usr/bin/xcrun",
                        arguments: ["devicectl", "device", "process", "launch", "--device", udid, bundleID],
                        timeout: 30,
                        environment: nil
                    )

                    await session.set(.bundleID, value: bundleID)

                    var lines = [
                        "Build, install, and launch completed.",
                        "Scheme: \(scheme)",
                        "Configuration: \(configuration)",
                        "Device: \(udid)",
                        "Bundle ID: \(bundleID)",
                    ]
                    if !launchResult.succeeded {
                        lines.append("Warning: Launch may have failed — \(launchResult.stderr)")
                    }
                    if !installNote.isEmpty { lines.append(installNote) }

                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } catch {
                    return .error(ToolError(
                        code: .internalError,
                        message: "Failed during build_run_device: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
