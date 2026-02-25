//
//  SwiftPackageInitTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerSwiftPackageInitTool(
    with registry: ToolRegistry,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swift_package_init",
        description: "Initialize a new Swift package in the specified directory.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Directory where the new package will be created (required)."
                ),
                "type": .init(
                    type: "string",
                    description: "Package type to create.",
                    enumValues: ["library", "executable", "tool", "macro", "empty"]
                ),
                "name": .init(
                    type: "string",
                    description: "Name for the new package. Defaults to the directory name."
                ),
            ],
            required: ["path"]
        ),
        category: .swiftPackage,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let path) = args["path"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "path is required for swift_package_init."
            ))
        }

        if let error = validator.validatePathExists(path, label: "Package directory") {
            return .error(error)
        }

        var arguments = ["package", "init", "--package-path", path]

        if case .string(let type) = args["type"] {
            arguments += ["--type", type]
        }
        if case .string(let name) = args["name"] {
            arguments += ["--name", name]
        }

        do {
            let result = try await executor.execute(
                executable: "/usr/bin/swift",
                arguments: arguments,
                timeout: 30,
                environment: nil
            )

            if result.succeeded {
                var lines = [
                    "Swift package initialized.",
                    "Path: \(path)",
                ]
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty { lines.append("\n\(output)") }
                return .success(ToolResult(content: lines.joined(separator: "\n")))
            } else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "swift package init failed.",
                    details: result.stderr
                ))
            }
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to run swift package init: \(error.localizedDescription)"
            ))
        }
    }
}
