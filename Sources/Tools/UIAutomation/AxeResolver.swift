//
//  AxeResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Locate the `axe` binary for UI automation.
///
/// Resolution order:
/// 1. Walk up from the main executable to find `Vendor/axe/<arch>/axe`
/// 2. Fall back to `which axe` via Process
/// 3. Return `.dependencyMissing` if neither succeeds
func resolveAxePath() -> Result<String, ToolError> {
    // 1. Check Vendor directory relative to executable
    if let execURL = Bundle.main.executableURL {
        let candidates = sequence(first: execURL.deletingLastPathComponent()) { url in
            let parent = url.deletingLastPathComponent()
            return parent.path != url.path ? parent : nil
        }

        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif

        for dir in candidates {
            let axePath = dir.appendingPathComponent("Vendor/axe/\(arch)/axe").path
            if FileManager.default.isExecutableFile(atPath: axePath) {
                return .success(axePath)
            }
        }
    }

    // 2. Fall back to PATH lookup
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["axe"]
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
        message: "axe CLI not found. Install axe to use UI automation tools. See: https://github.com/nicklama/axe"
    ))
}
