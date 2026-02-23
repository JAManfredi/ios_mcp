//
//  LLDBDenylist.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

// MARK: - DenylistResult

/// Result of checking an LLDB command against the denylist.
public enum DenylistResult: Sendable, Equatable {
    case allowed
    case denied(reason: String, suggestion: String)
}

// MARK: - Denylist Check

/// Checks an LLDB command against the denylist of blocked command prefixes.
/// Returns `.allowed` if the command is safe, or `.denied` with reason and suggestion.
public func checkDenylist(command: String) -> DenylistResult {
    let trimmed = command.trimmingCharacters(in: .whitespaces)

    for entry in denylistEntries {
        if entry.matches(trimmed) {
            return .denied(reason: entry.reason, suggestion: entry.suggestion)
        }
    }

    return .allowed
}

// MARK: - Denylist Entries

private struct DenylistEntry: Sendable {
    let prefix: String
    let reason: String
    let suggestion: String
    let additionalCheck: (@Sendable (String) -> Bool)?

    init(
        prefix: String,
        reason: String,
        suggestion: String,
        additionalCheck: (@Sendable (String) -> Bool)? = nil
    ) {
        self.prefix = prefix
        self.reason = reason
        self.suggestion = suggestion
        self.additionalCheck = additionalCheck
    }

    func matches(_ command: String) -> Bool {
        guard command.hasPrefix(prefix) else { return false }
        if let additionalCheck { return additionalCheck(command) }
        return true
    }
}

private let denylistEntries: [DenylistEntry] = [
    DenylistEntry(
        prefix: "platform shell",
        reason: "Arbitrary shell execution",
        suggestion: "Use MCP tools for shell operations"
    ),
    DenylistEntry(
        prefix: "command script",
        reason: "Arbitrary Python scripts",
        suggestion: "Not available in this context"
    ),
    DenylistEntry(
        prefix: "command source",
        reason: "Source arbitrary command files",
        suggestion: "Not available in this context"
    ),
    DenylistEntry(
        prefix: "process kill",
        reason: "Kill target process",
        suggestion: "Use `stop_app` tool instead"
    ),
    DenylistEntry(
        prefix: "process destroy",
        reason: "Destroy target process",
        suggestion: "Use `stop_app` tool instead"
    ),
    DenylistEntry(
        prefix: "memory write",
        reason: "Arbitrary memory mutation",
        suggestion: "Use read-only inspection commands"
    ),
    DenylistEntry(
        prefix: "register write",
        reason: "Register mutation",
        suggestion: "Use read-only inspection commands"
    ),
    DenylistEntry(
        prefix: "expression",
        reason: "Load arbitrary frameworks",
        suggestion: "Use `expression` without `@import`",
        additionalCheck: { command in
            let afterPrefix = command.dropFirst("expression".count)
            return afterPrefix.contains("@import")
        }
    ),
    DenylistEntry(
        prefix: "settings set target.run-args",
        reason: "Modify launch arguments",
        suggestion: "Use `build_run_sim` to set launch args"
    ),
    DenylistEntry(
        prefix: "target delete",
        reason: "Remove debug target",
        suggestion: "Use `debug_detach` instead"
    ),
]
