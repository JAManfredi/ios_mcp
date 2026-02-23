//
//  ShowBuildSettingsTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

private let curatedKeys: Set<String> = [
    "PRODUCT_BUNDLE_IDENTIFIER",
    "PRODUCT_NAME",
    "PRODUCT_MODULE_NAME",
    "SDKROOT",
    "SUPPORTED_PLATFORMS",
    "IPHONEOS_DEPLOYMENT_TARGET",
    "MACOSX_DEPLOYMENT_TARGET",
    "SWIFT_VERSION",
    "SWIFT_OPTIMIZATION_LEVEL",
    "CONFIGURATION",
    "BUILD_DIR",
    "BUILT_PRODUCTS_DIR",
    "DERIVED_DATA_DIR",
    "TARGET_BUILD_DIR",
    "CODE_SIGN_IDENTITY",
    "CODE_SIGN_STYLE",
    "DEVELOPMENT_TEAM",
    "INFOPLIST_FILE",
    "GENERATE_INFOPLIST_FILE",
]

func registerShowBuildSettingsTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "show_build_settings",
        description: "Show curated Xcode build settings for a scheme. Displays a focused subset (~19 key settings) instead of the full 500+ settings dump. Falls back to session defaults for workspace, project, scheme, and configuration. Automatically sets session bundle ID and configuration.",
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
                    description: "Build configuration (e.g., Debug, Release). Falls back to session default."
                ),
            ]
        ),
        category: .projectDiscovery,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        do {
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

            let configuration: String?
            if case .string(let c) = args["configuration"] {
                configuration = c
            } else {
                configuration = await session.get(.configuration)
            }

            guard let scheme else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No scheme specified, and no session default is set. Run list_schemes first."
                ))
            }

            var xcodebuildArgs = ["-showBuildSettings", "-scheme", scheme]

            if let workspace {
                xcodebuildArgs += ["-workspace", workspace]
            } else if let project {
                xcodebuildArgs += ["-project", project]
            } else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No workspace or project specified, and no session default is set. Run discover_projects first."
                ))
            }

            if let configuration {
                xcodebuildArgs += ["-configuration", configuration]
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcodebuild",
                arguments: xcodebuildArgs,
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "xcodebuild -showBuildSettings failed",
                    details: result.stderr
                ))
            }

            let allSettings = parseBuildSettings(result.stdout)
            let curated = allSettings.filter { curatedKeys.contains($0.key) }

            let configLabel = configuration ?? allSettings["CONFIGURATION"] ?? "Default"
            var lines: [String] = ["Build settings for scheme '\(scheme)' (configuration: \(configLabel)):\n"]

            for key in curated.keys.sorted() {
                lines.append("  \(key) = \(curated[key]!)")
            }

            if curated.isEmpty {
                lines.append("  (no curated settings found)")
            }

            if let bundleID = curated["PRODUCT_BUNDLE_IDENTIFIER"], !bundleID.isEmpty {
                await session.set(.bundleID, value: bundleID)
                lines.append("\nSession default set: bundle_id = \(bundleID)")
            }

            if let deployTarget = curated["IPHONEOS_DEPLOYMENT_TARGET"], !deployTarget.isEmpty {
                await session.set(.deploymentTarget, value: deployTarget)
            }

            if case .string = args["configuration"] {
                if let config = configuration {
                    await session.set(.configuration, value: config)
                    lines.append("Session default set: configuration = \(config)")
                }
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to show build settings: \(error.localizedDescription)"
            ))
        }
    }
}

// MARK: - Parser

func parseBuildSettings(_ output: String) -> [String: String] {
    var settings: [String: String] = [:]

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let equalsRange = trimmed.range(of: " = ") else { continue }

        let key = String(trimmed[trimmed.startIndex..<equalsRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[equalsRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        if !key.isEmpty {
            settings[key] = value
        }
    }

    return settings
}
