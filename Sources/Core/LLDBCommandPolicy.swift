//
//  LLDBCommandPolicy.swift
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

/// Checks an LLDB command against the denylist of blocked commands.
/// Aliases and abbreviations are expanded first, so `r`, `attach`, and
/// `pro la` are checked as the commands LLDB would actually run.
/// Returns `.allowed` if the command is safe, or `.denied` with reason and suggestion.
public func checkDenylist(command: String) -> DenylistResult {
    for candidate in lldbCommandCandidates(command) {
        for entry in denylistEntries where entry.matches(candidate, command: command) {
            return .denied(reason: entry.reason, suggestion: entry.suggestion)
        }
    }

    return .allowed
}

// MARK: - Session Protocol Check

/// Rejects commands that would break the one-command/one-reply protocol used by
/// `LLDBSession`. Unlike the denylist, `allow_unsafe` cannot bypass this:
/// LLDB answers confirmation prompts from stdin, so the session only stays in
/// sync while `auto-confirm` remains enabled and LLDB itself keeps running.
func lldbSessionProtocolError(_ command: String) -> ToolError? {
    guard !command.contains("\n"), !command.contains("\r") else {
        return ToolError(code: .invalidInput, message: "Send one LLDB command per request; multiline interactive input is not supported.")
    }

    let words = lldbWords(command)
    for candidate in lldbCommandCandidates(command) {
        if candidate.first == "quit" {
            return ToolError(code: .invalidInput, message: "Use debug_detach to close a debug session; quit is not supported.")
        }
        guard candidate.first == "settings", candidate.count >= 2 else { continue }
        let subcommand = candidate[1]
        guard lldbSettingsMutations.contains(subcommand) else { continue }
        let changesAutoConfirm = subcommand == "read"
            || (subcommand == "clear" && words.contains { $0 == "-a" || $0 == "--all" })
            || command.lowercased().contains("auto-confirm")
        if changesAutoConfirm {
            return ToolError(code: .invalidInput, message: "debug sessions require LLDB auto-confirm to stay enabled; `settings \(subcommand)` cannot change it here.")
        }
    }
    return nil
}

// MARK: - Command Resolution

/// Returns every command LLDB could resolve `command` to, as canonical words
/// followed by the remaining arguments.
///
/// LLDB runs an exact alias first, then any unambiguous prefix of a command or
/// alias (`pro la` is `process launch`, `ru` is `run`). Only the paths that can
/// reach a policed command are expanded. An ambiguous prefix expands to every
/// policed match; LLDB rejects it anyway, so denying it costs nothing.
func lldbCommandCandidates(_ command: String) -> [[String]] {
    let words = lldbWords(command)
    guard let first = words.first else { return [] }
    let rest = Array(words.dropFirst())

    let heads: [[String]]
    if let alias = lldbAliases[first] {
        heads = [alias]
    } else if lldbPolicedCommands.contains(first) || first.count < 2 {
        heads = [[first]]
    } else {
        let commands = lldbPolicedCommands.filter { $0.hasPrefix(first) }.map { [$0] }
        let aliases = lldbAliases.keys.filter { $0.count >= 2 && $0.hasPrefix(first) }.sorted().compactMap { lldbAliases[$0] }
        heads = commands + aliases
    }
    if heads.isEmpty { return [words] }
    return heads.flatMap { expandSubcommands(path: $0, rest: rest) }
}

private func expandSubcommands(path: [String], rest: [String]) -> [[String]] {
    guard let next = rest.first, let subcommands = lldbPolicedSubcommands[path.joined(separator: " ")] else {
        return [path + rest]
    }
    let matches = subcommands.filter { $0.hasPrefix(next) }
    if matches.isEmpty { return [path + rest] }
    return matches.flatMap { expandSubcommands(path: path + [$0], rest: Array(rest.dropFirst())) }
}

private func lldbWords(_ command: String) -> [String] {
    command.split(whereSeparator: \.isWhitespace).map(String.init)
}

/// Built-in aliases that reach a policed command (`help` lists them under
/// "Current command abbreviations").
private let lldbAliases: [String: [String]] = [
    "r": ["process", "launch"],
    "run": ["process", "launch"],
    "attach": ["process", "attach"],
    "_regexp-attach": ["process", "attach"],
    "kill": ["process", "kill"],
    "gdb-remote": ["process", "connect"],
    "kdp-remote": ["process", "connect"],
    "shell": ["platform", "shell"],
    "re": ["register"],
    "e": ["expression"],
    "expr": ["expression"],
    "p": ["expression"],
    "po": ["expression"],
    "print": ["expression"],
    "call": ["expression"],
    "parray": ["expression"],
    "poarray": ["expression"],
    "dwim-print": ["expression"],
    "q": ["quit"],
    "exit": ["quit"],
]

private let lldbPolicedCommands = [
    "command", "expression", "memory", "platform", "process", "quit", "register", "script", "settings", "target",
]

/// Subcommands that a denylist entry or the session protocol check cares about.
private let lldbPolicedSubcommands: [String: [String]] = [
    "process": ["attach", "connect", "destroy", "kill", "launch"],
    "platform": ["process", "shell"],
    "platform process": ["attach", "launch"],
    "target": ["delete"],
    "memory": ["write"],
    "register": ["write"],
    "command": ["alias", "regex", "script", "source"],
    "settings": lldbSettingsMutations,
]

/// `settings` subcommands that change values (`read` loads them from a file).
private let lldbSettingsMutations = ["append", "clear", "insert-after", "insert-before", "read", "remove", "replace", "set"]

// MARK: - Denylist Entries

private struct DenylistEntry: Sendable {
    let prefix: String
    let reason: String
    let suggestion: String
    let additionalCheck: (@Sendable (_ candidate: [String], _ command: String) -> Bool)?

    init(
        prefix: String,
        reason: String,
        suggestion: String,
        additionalCheck: (@Sendable (_ candidate: [String], _ command: String) -> Bool)? = nil
    ) {
        self.prefix = prefix
        self.reason = reason
        self.suggestion = suggestion
        self.additionalCheck = additionalCheck
    }

    /// Matches whole words of the resolved command; `additionalCheck` also sees
    /// the command as written.
    func matches(_ candidate: [String], command: String) -> Bool {
        let words = prefix.split(separator: " ").map(String.init)
        guard candidate.starts(with: words) else { return false }
        if let additionalCheck { return additionalCheck(candidate, command) }
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
        prefix: "script",
        reason: "Arbitrary Python scripts",
        suggestion: "Not available in this context"
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
        prefix: "command alias",
        reason: "User-defined commands bypass this denylist",
        suggestion: "Run the full command instead"
    ),
    DenylistEntry(
        prefix: "command regex",
        reason: "User-defined commands bypass this denylist",
        suggestion: "Run the full command instead"
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
        prefix: "process launch",
        reason: "Relaunch kills the attached process",
        suggestion: "Use `build_run_simulator` or `launch_app`, then `debug_attach`"
    ),
    DenylistEntry(
        prefix: "process attach",
        reason: "Attach replaces the current debug target",
        suggestion: "Use `debug_detach`, then `debug_attach`"
    ),
    DenylistEntry(
        prefix: "process connect",
        reason: "Connect replaces the current debug target",
        suggestion: "Use `debug_detach`, then `debug_attach`"
    ),
    DenylistEntry(
        prefix: "platform process launch",
        reason: "Launch a process outside the debug session",
        suggestion: "Use `launch_app` instead"
    ),
    DenylistEntry(
        prefix: "platform process attach",
        reason: "Attach replaces the current debug target",
        suggestion: "Use `debug_detach`, then `debug_attach`"
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
        additionalCheck: { _, command in command.contains("@import") }
    ),
    DenylistEntry(
        prefix: "settings",
        reason: "Modify launch arguments",
        suggestion: "Use `build_run_simulator` to set launch args",
        additionalCheck: { candidate, command in
            candidate.count >= 2 && lldbSettingsMutations.contains(candidate[1]) && command.contains("target.run-args")
        }
    ),
    DenylistEntry(
        prefix: "target delete",
        reason: "Remove debug target",
        suggestion: "Use `debug_detach` instead"
    ),
]
