//
//  XcodebuildPhaseParser.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Parses xcodebuild stdout lines for build phase transitions.
/// Returns a human-readable phase name when the phase changes, nil otherwise.
/// Deduplicates consecutive identical phases.
/// Actor isolation makes it safe to use from `@Sendable` streaming callbacks.
actor XcodebuildPhaseParser {
    private var lastPhase: String?

    /// Parse a single line of xcodebuild output.
    /// Returns a phase name if this line represents a new phase, nil otherwise.
    func parse(line: String) -> String? {
        guard let phase = Self.extractPhase(from: line) else { return nil }
        guard phase != lastPhase else { return nil }
        lastPhase = phase
        return phase
    }

    private static func extractPhase(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("CompileC ") || trimmed.hasPrefix("CompileSwift ") || trimmed.hasPrefix("CompileSwiftSources") {
            return "Compiling"
        }
        if trimmed.hasPrefix("Ld ") || trimmed.hasPrefix("Linking ") {
            return "Linking"
        }
        if trimmed.hasPrefix("CopySwiftLibs") {
            return "Copying Swift libraries"
        }
        if trimmed.hasPrefix("CodeSign ") {
            return "Code signing"
        }
        if trimmed.hasPrefix("ProcessInfoPlistFile") || trimmed.hasPrefix("CopyPlistFile") {
            return "Processing plists"
        }
        if trimmed.hasPrefix("CompileAssetCatalog") {
            return "Compiling assets"
        }
        if trimmed.hasPrefix("CompileStoryboard") || trimmed.hasPrefix("CompileXIB") || trimmed.hasPrefix("LinkStoryboards") {
            return "Compiling storyboards"
        }
        if trimmed.hasPrefix("Test Suite ") || trimmed.hasPrefix("Testing ") {
            return "Running tests"
        }
        if trimmed.hasPrefix("MergeSwiftModule") {
            return "Merging Swift module"
        }
        if trimmed.hasPrefix("GenerateDSYMFile") {
            return "Generating dSYM"
        }
        if trimmed.hasPrefix("PhaseScriptExecution") {
            return "Running build script"
        }

        return nil
    }
}
