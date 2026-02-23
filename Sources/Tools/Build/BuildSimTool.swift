//
//  BuildSimTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerBuildSimTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "build_sim",
        description: "Build an Xcode project for the iOS Simulator. Falls back to session defaults for workspace, project, scheme, configuration, udid, and derived_data_path. Returns error/warning counts and xcresult artifact path.",
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
            owner: "build_sim"
        ) {
            do {
                let timestamp = Int(Date().timeIntervalSince1970)
                let resultPath = NSTemporaryDirectory() + "\(resolved.scheme)_build_\(timestamp).xcresult"

                // Remove stale xcresult if it exists
                try? FileManager.default.removeItem(atPath: resultPath)

                var buildArgs = xcodebuildBaseArgs(from: resolved, resultBundlePath: resultPath)
                buildArgs.append("build")

                let timeout: TimeInterval = min(
                    args["timeout"].flatMap { if case .int(let t) = $0 { Double(t) } else { nil } } ?? 1200,
                    2700
                )

                let buildStart = ContinuousClock.now
                let result = try await executor.execute(
                    executable: "/usr/bin/xcodebuild",
                    arguments: buildArgs,
                    timeout: timeout,
                    environment: nil
                )

                let diagnostics = await fetchBuildDiagnostics(
                    resultBundlePath: resultPath,
                    executor: executor
                )
                let elapsed = ContinuousClock.now - buildStart

                var lines: [String] = []

                if result.succeeded {
                    lines.append("Build succeeded for scheme '\(resolved.scheme)'.")
                } else {
                    lines.append("Build failed for scheme '\(resolved.scheme)'.")
                }

                lines.append(String(format: "Elapsed: %.1fs", durationSeconds(elapsed)))
                lines.append("Errors: \(diagnostics.errors.count), Warnings: \(diagnostics.warnings.count)")

                for error in diagnostics.errors {
                    var errorLine = "  error: \(error.message)"
                    if let file = error.file { errorLine += " (\(file):\(error.line ?? 0))" }
                    lines.append(errorLine)
                }

                for warning in diagnostics.warnings.prefix(10) {
                    var warnLine = "  warning: \(warning.message)"
                    if let file = warning.file { warnLine += " (\(file):\(warning.line ?? 0))" }
                    lines.append(warnLine)
                }

                lines.append("xcresult: \(resultPath)")

                if result.succeeded {
                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: lines.joined(separator: "\n"),
                        details: result.stderr
                    ))
                }
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Build failed: \(error.localizedDescription)"
                ))
            }
        }
    }
}
