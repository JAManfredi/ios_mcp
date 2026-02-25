//
//  PackagePathResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

/// Resolves the Swift package root directory from explicit args or session defaults.
///
/// Resolution order:
/// 1. Explicit `path` argument
/// 2. Parent directory of session workspace (`.xcworkspace` lives inside the package root)
/// 3. Parent directory of session project
/// 4. Error: no package path available
func resolvePackagePath(
    from args: [String: Value],
    session: SessionStore,
    validator: DefaultsValidator
) async -> Result<String, ToolError> {
    let path: String

    if case .string(let explicit) = args["path"] {
        path = explicit
    } else if let workspace = await session.get(.workspace) {
        path = (workspace as NSString).deletingLastPathComponent
    } else if let project = await session.get(.project) {
        path = (project as NSString).deletingLastPathComponent
    } else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No package path specified and no workspace or project set in session defaults. Provide a 'path' argument or run discover_projects first."
        ))
    }

    if let error = validator.validatePathExists(path, label: "Package directory") {
        return .failure(error)
    }

    return .success(path)
}
