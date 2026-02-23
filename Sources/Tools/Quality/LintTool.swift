//
//  LintTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

/// Locate the `swiftlint` binary via PATH lookup.
///
/// Uses `which swiftlint` via Process. Returns `.dependencyMissing` if not found.
func resolveSwiftLintPath() -> Result<String, ToolError> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["swiftlint"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty {
                return .success(path)
            }
        }
    } catch {
        // Fall through to dependency_missing
    }

    return .failure(ToolError(
        code: .dependencyMissing,
        message: "swiftlint not found. Install SwiftLint to use the lint tool. See: https://github.com/realm/SwiftLint"
    ))
}

func registerLintTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    swiftLintPath: String? = nil,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "lint",
        description: "Run SwiftLint on a directory or file. Returns lint violations as JSON by default. Falls back to session workspace or project path.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Directory or file to lint. Falls back to session workspace or project."
                ),
                "reporter": .init(
                    type: "string",
                    description: "SwiftLint reporter format (e.g. json, xcode). Defaults to json."
                ),
            ]
        ),
        category: .quality
    )

    await registry.register(manifest: manifest) { args in
        // 1. Resolve swiftlint path
        let resolvedSwiftLint: String
        if let swiftLintPath {
            resolvedSwiftLint = swiftLintPath
        } else {
            switch resolveSwiftLintPath() {
            case .success(let path): resolvedSwiftLint = path
            case .failure(let error): return .error(error)
            }
        }

        // 2. Resolve path to lint
        var path: String?
        if case .string(let p) = args["path"], !p.isEmpty {
            path = p
        }
        if path == nil {
            path = await session.get(.workspace)
        }
        if path == nil {
            path = await session.get(.project)
        }
        guard let resolvedPath = path else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No path provided and no session workspace or project is set."
            ))
        }

        if let error = validator.validatePathExists(resolvedPath, label: "Lint path") {
            return .error(error)
        }

        // 3. Resolve reporter
        var reporter = "json"
        if case .string(let r) = args["reporter"], !r.isEmpty {
            reporter = r
        }

        // 4. Execute
        do {
            let result = try await executor.execute(
                executable: resolvedSwiftLint,
                arguments: ["lint", "--path", resolvedPath, "--reporter", reporter],
                timeout: 300,
                environment: nil
            )

            // Exit code 0 = clean, 1 = violations found (still success), 2+ = fatal error
            if result.exitCode >= 2 {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "swiftlint lint failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(content: result.stdout))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to run swiftlint: \(error.localizedDescription)"
            ))
        }
    }
}
