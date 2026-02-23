//
//  ListSchemesTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerListSchemesTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "list_schemes",
        description: "List Xcode schemes, targets, and build configurations for a workspace or project. Falls back to session defaults if workspace/project are not provided. Automatically sets session default scheme when exactly one scheme is found.",
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

            var xcodebuildArgs = ["-list"]
            let contextLabel: String

            if let workspace {
                xcodebuildArgs += ["-workspace", workspace]
                contextLabel = workspace
            } else if let project {
                xcodebuildArgs += ["-project", project]
                contextLabel = project
            } else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "No workspace or project specified, and no session default is set. Run discover_projects first."
                ))
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
                    message: "xcodebuild -list failed",
                    details: result.stderr
                ))
            }

            let parsed = parseXcodebuildList(result.stdout)

            var lines: [String] = ["Xcode project info for \(contextLabel):\n"]

            if !parsed.schemes.isEmpty {
                lines.append("Schemes:")
                for scheme in parsed.schemes {
                    lines.append("  - \(scheme)")
                }
            }

            if !parsed.targets.isEmpty {
                lines.append("\nTargets:")
                for target in parsed.targets {
                    lines.append("  - \(target)")
                }
            }

            if !parsed.configurations.isEmpty {
                lines.append("\nBuild Configurations:")
                for config in parsed.configurations {
                    lines.append("  - \(config)")
                }
            }

            if parsed.schemes.count == 1 {
                await session.set(.scheme, value: parsed.schemes[0])
                lines.append("\nSession default set: scheme = \(parsed.schemes[0])")
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to list schemes: \(error.localizedDescription)"
            ))
        }
    }
}

// MARK: - Parser

struct XcodebuildListOutput: Sendable {
    var schemes: [String] = []
    var targets: [String] = []
    var configurations: [String] = []
}

func parseXcodebuildList(_ output: String) -> XcodebuildListOutput {
    var result = XcodebuildListOutput()

    enum Section {
        case none, schemes, targets, configurations
    }

    var currentSection: Section = .none

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            currentSection = .none
            continue
        }

        if trimmed.hasSuffix(":") {
            let header = trimmed.dropLast().trimmingCharacters(in: .whitespaces).lowercased()
            switch header {
            case "schemes": currentSection = .schemes
            case "targets": currentSection = .targets
            case "build configurations": currentSection = .configurations
            default: currentSection = .none
            }
            continue
        }

        switch currentSection {
        case .schemes: result.schemes.append(trimmed)
        case .targets: result.targets.append(trimmed)
        case .configurations: result.configurations.append(trimmed)
        case .none: break
        }
    }

    return result
}
