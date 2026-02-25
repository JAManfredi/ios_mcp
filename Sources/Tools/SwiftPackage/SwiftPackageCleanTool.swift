//
//  SwiftPackageCleanTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerSwiftPackageCleanTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swift_package_clean",
        description: "Clean Swift package build artifacts. Falls back to session workspace or project parent directory for the package path.",
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
                    arguments: ["package", "clean", "--package-path", packagePath],
                    timeout: 30,
                    environment: nil
                )

                if result.succeeded {
                    return .success(ToolResult(content: "Package build artifacts cleaned.\nPackage path: \(packagePath)"))
                } else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "swift package clean failed.",
                        details: result.stderr
                    ))
                }
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to run swift package clean: \(error.localizedDescription)"
                ))
            }
        }
    }
}
