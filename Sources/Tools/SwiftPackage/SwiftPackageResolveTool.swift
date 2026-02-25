//
//  SwiftPackageResolveTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerSwiftPackageResolveTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swift_package_resolve",
        description: "Resolve Swift package dependencies. Falls back to session workspace or project parent directory for the package path.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the Swift package directory containing Package.swift. Falls back to session workspace or project parent directory."
                ),
            ]
        ),
        category: .swiftPackage
    )

    await registry.register(manifest: manifest) { args in
        switch await resolvePackagePath(from: args, session: session, validator: validator) {
        case .failure(let error):
            return .error(error)
        case .success(let packagePath):
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/swift",
                    arguments: ["package", "resolve", "--package-path", packagePath],
                    timeout: 300,
                    environment: nil
                )

                if result.succeeded {
                    var lines = [
                        "Package dependencies resolved.",
                        "Package path: \(packagePath)",
                    ]
                    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !output.isEmpty { lines.append("\n\(output)") }
                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: "swift package resolve failed.",
                        details: result.stderr
                    ))
                }
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to run swift package resolve: \(error.localizedDescription)"
                ))
            }
        }
    }
}
