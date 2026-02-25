//
//  SwiftPackageUpdateTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerSwiftPackageUpdateTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swift_package_update",
        description: "Update Swift package dependencies to the latest allowed versions. Falls back to session workspace or project parent directory for the package path.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the Swift package directory containing Package.swift. Falls back to session workspace or project parent directory."
                ),
            ]
        ),
        category: .swiftPackage,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        switch await resolvePackagePath(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let packagePath):
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/swift",
                    arguments: ["package", "--package-path", packagePath, "update"],
                    timeout: 300,
                    environment: nil
                )

                if result.succeeded {
                    var lines = [
                        "Package dependencies updated.",
                        "Package path: \(packagePath)",
                    ]
                    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !output.isEmpty { lines.append("\n\(output)") }
                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "swift package update failed.",
                        details: result.stderr
                    ))
                }
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to run swift package update: \(error.localizedDescription)"
                ))
            }
        }
    }
}
