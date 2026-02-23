//
//  PathPolicy.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Validates that filesystem paths fall within allowed root directories.
/// Rejects access to paths outside the user's home, temp directories, and /var/folders.
public struct PathPolicy: Sendable {
    private let allowedRoots: [String]

    public init(allowedRoots: [String]? = nil) {
        self.allowedRoots = allowedRoots ?? Self.defaultAllowedRoots()
    }

    /// Validates that a path is under an allowed root.
    /// Returns nil if allowed, ToolError if rejected.
    public func validate(
        _ path: String,
        label: String
    ) -> ToolError? {
        let resolved = (path as NSString).standardizingPath

        for root in allowedRoots {
            if resolved.hasPrefix(root) { return nil }
        }

        return ToolError(
            code: .invalidInput,
            message: "\(label) path is outside allowed directories: \(path). Paths must be under your home directory or system temp directories."
        )
    }

    private static func defaultAllowedRoots() -> [String] {
        var roots: [String] = []

        // User home directory
        let home = NSHomeDirectory()
        if !home.isEmpty {
            roots.append(home)
        }

        // System and user temp directories
        roots.append("/tmp")
        roots.append("/private/tmp")
        roots.append("/var/folders")

        let nsTmp = NSTemporaryDirectory()
        if !nsTmp.isEmpty {
            roots.append((nsTmp as NSString).standardizingPath)
        }

        return roots
    }
}
