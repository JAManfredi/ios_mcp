//
//  BuildRunSimTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerBuildRunSimTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "build_run_sim",
        description: "Build, install, and launch an app on the iOS Simulator. Falls back to session defaults for workspace, project, scheme, configuration, udid, and derived_data_path. Automatically resolves the app path from build settings and sets session bundle_id.",
        inputSchema: JSONSchema(
            properties: [
                "workspace": .init(
                    type: "string",
                    description: "Path to .xcworkspace. Falls back to session default."
                ),
                "project": .init(
                    type: "string",
                    description: "Path to .xcodeproj. Falls back to session default. Ignored if workspace is provided."
                ),
                "scheme": .init(
                    type: "string",
                    description: "Scheme name. Falls back to session default."
                ),
                "configuration": .init(
                    type: "string",
                    description: "Build configuration (e.g., Debug, Release). Falls back to session default, then Debug."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "derived_data_path": .init(
                    type: "string",
                    description: "Custom DerivedData path. Falls back to session default."
                ),
                "extra_args": .init(
                    type: "string",
                    description: "Additional xcodebuild arguments, space-separated."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "App bundle identifier. Auto-resolved from build settings if not provided."
                ),
                "launch_args": .init(
                    type: "string",
                    description: "Space-separated launch arguments to pass to the app."
                ),
            ]
        ),
        category: .build
    )

    await registry.register(manifest: manifest) { args in
        let resolved: ResolvedBuildArgs
        switch await resolveBuildArgs(from: args, session: session, validator: validator) {
        case .success(let r): resolved = r
        case .failure(let error): return .error(error)
        }

        return await concurrency.withLock(
            key: resolved.lockKey,
            owner: "build_run_sim"
        ) {
            do {
                let overallStart = ContinuousClock.now

                // Step 1: Build
                let timestamp = Int(Date().timeIntervalSince1970)
                let resultPath = NSTemporaryDirectory() + "\(resolved.scheme)_buildrun_\(timestamp).xcresult"

                try? FileManager.default.removeItem(atPath: resultPath)

                var buildArgs = xcodebuildBaseArgs(from: resolved, resultBundlePath: resultPath)
                buildArgs.append("build")

                let buildTimeout: TimeInterval = min(
                    args["timeout"].flatMap { if case .int(let t) = $0 { Double(t) } else { nil } } ?? 1200,
                    2700
                )

                let buildStart = ContinuousClock.now
                let buildResult = try await executor.execute(
                    executable: "/usr/bin/xcodebuild",
                    arguments: buildArgs,
                    timeout: buildTimeout,
                    environment: nil
                )
                let buildElapsed = ContinuousClock.now - buildStart

                guard buildResult.succeeded else {
                    let diagnostics = await fetchBuildDiagnostics(
                        resultBundlePath: resultPath,
                        executor: executor
                    )
                    var lines = ["Build failed for scheme '\(resolved.scheme)'."]
                    lines.append(String(format: "Elapsed: %.1fs", durationSeconds(buildElapsed)))
                    lines.append("Errors: \(diagnostics.errors.count)")
                    for error in diagnostics.errors {
                        lines.append("  error: \(error.message)")
                    }
                    return .error(ToolError(
                        code: .commandFailed,
                        message: lines.joined(separator: "\n"),
                        details: buildResult.stderr
                    ))
                }

                // Step 2: Resolve app path + bundle ID from build settings
                var settingsArgs: [String] = ["-showBuildSettings", "-scheme", resolved.scheme]
                if let ws = resolved.workspaceArg {
                    settingsArgs += ["-workspace", ws]
                } else if let proj = resolved.projectArg {
                    settingsArgs += ["-project", proj]
                }
                settingsArgs += ["-configuration", resolved.configuration]

                let settingsResult = try await executor.execute(
                    executable: "/usr/bin/xcodebuild",
                    arguments: settingsArgs,
                    timeout: 30,
                    environment: nil
                )

                let settings = parseBuildSettings(settingsResult.stdout)
                let builtProductsDir = settings["BUILT_PRODUCTS_DIR"] ?? ""
                let fullProductName = settings["FULL_PRODUCT_NAME"] ?? ""
                let appPath = builtProductsDir + "/" + fullProductName

                let bundleID: String
                if case .string(let explicit) = args["bundle_id"] {
                    bundleID = explicit
                } else if let settingsBundleID = settings["PRODUCT_BUNDLE_IDENTIFIER"], !settingsBundleID.isEmpty {
                    bundleID = settingsBundleID
                } else if let sessionBundleID = await session.get(.bundleID) {
                    bundleID = sessionBundleID
                } else {
                    return .error(ToolError(
                        code: .invalidInput,
                        message: "Could not resolve bundle_id from build settings or session. Provide bundle_id explicitly."
                    ))
                }

                // Auto-set session bundle_id
                await session.set(.bundleID, value: bundleID)

                // Step 3: Install
                let installStart = ContinuousClock.now
                let installResult = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["simctl", "install", resolved.udid, appPath],
                    timeout: 60,
                    environment: nil
                )
                let installElapsed = ContinuousClock.now - installStart

                guard installResult.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl install failed",
                        details: installResult.stderr
                    ))
                }

                // Step 4: Launch
                var launchArgs = ["simctl", "launch", resolved.udid, bundleID]
                if case .string(let la) = args["launch_args"] {
                    launchArgs += la.components(separatedBy: " ").filter { !$0.isEmpty }
                }

                let launchStart = ContinuousClock.now
                let launchResult = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: launchArgs,
                    timeout: 60,
                    environment: nil
                )
                let launchElapsed = ContinuousClock.now - launchStart

                guard launchResult.succeeded else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "simctl launch failed",
                        details: launchResult.stderr
                    ))
                }

                let overallElapsed = ContinuousClock.now - overallStart

                var lines = [
                    "Build, install, and launch succeeded for scheme '\(resolved.scheme)'.",
                    "Bundle ID: \(bundleID)",
                    "Simulator: \(resolved.udid)",
                ]

                let pid = launchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pid.isEmpty { lines.append("PID: \(pid)") }

                lines.append(String(format: "Timing: build %.1fs, install %.1fs, launch %.1fs (total %.1fs)",
                    durationSeconds(buildElapsed),
                    durationSeconds(installElapsed),
                    durationSeconds(launchElapsed),
                    durationSeconds(overallElapsed)))
                lines.append("Session default set: bundle_id = \(bundleID)")
                lines.append("xcresult: \(resultPath)")

                return .success(ToolResult(content: lines.joined(separator: "\n")))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Build and run failed: \(error.localizedDescription)"
                ))
            }
        }
    }
}
