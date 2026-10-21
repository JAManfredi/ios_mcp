//
//  LLDBDenylistTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("LLDB Denylist")
struct LLDBDenylistTests {

    @Test("Allows safe commands")
    func allowsSafeCommand() {
        #expect(checkDenylist(command: "bt") == .allowed)
        #expect(checkDenylist(command: "frame variable") == .allowed)
        #expect(checkDenylist(command: "breakpoint set --name viewDidLoad") == .allowed)
        #expect(checkDenylist(command: "memory region 0x1000") == .allowed)
    }

    @Test("Blocks shell escape")
    func blocksShellEscape() {
        let result = checkDenylist(command: "platform shell ls")
        if case .denied(let reason, _) = result {
            #expect(reason.contains("shell"))
        } else {
            Issue.record("Expected denied result")
        }
    }

    @Test("Blocks script execution")
    func blocksScriptExecution() {
        let result = checkDenylist(command: "command script import mymodule")
        if case .denied(let reason, _) = result {
            #expect(reason.contains("Python"))
        } else {
            Issue.record("Expected denied result")
        }
    }

    @Test("Blocks process kill")
    func blocksProcessKill() {
        let result = checkDenylist(command: "process kill")
        if case .denied(let reason, _) = result {
            #expect(reason.contains("Kill"))
        } else {
            Issue.record("Expected denied result")
        }
    }

    @Test("Blocks memory write")
    func blocksMemoryWrite() {
        let result = checkDenylist(command: "memory write 0x1000 0xFF")
        if case .denied(let reason, _) = result {
            #expect(reason.contains("memory"))
        } else {
            Issue.record("Expected denied result")
        }
    }

    @Test("Blocks expression with @import")
    func blocksExpressionImport() {
        let result = checkDenylist(command: "expression @import UIKit")
        if case .denied(let reason, _) = result {
            #expect(reason.contains("framework"))
        } else {
            Issue.record("Expected denied result")
        }
    }

    @Test("Allows plain expression without @import")
    func allowsPlainExpression() {
        #expect(checkDenylist(command: "expression myVar") == .allowed)
        #expect(checkDenylist(command: "expression (int)someFunc()") == .allowed)
    }

    @Test("Resolves aliases and abbreviations before checking")
    func blocksAliasesAndAbbreviations() {
        let denied = [
            "r", "run", "ru", "process launch", "pro la", "proc l -- arg", "pr launch",
            "attach 42", "att 42", "_regexp-attach 42", "process attach --pid 42", "proc a -p 42",
            "process connect connect://localhost:1", "gdb-remote 1234", "kdp-remote host",
            "platform process launch /usr/bin/true", "pl pro att -p 42",
            "kill", "ki", "pro k", "process destroy",
            "shell ls", "sh ls", "script print(1)", "scr print(1)",
            "command alias relaunch process launch", "co a relaunch process launch", "command regex x",
            "re w pc 0", "reg write pc 0", "mem w 0x1000 0",
            "p @import UIKit", "po @import UIKit", "e @import UIKit", "expr @import UIKit",
            "se se -- target.run-args x", "target delete", "ta del",
        ]
        for command in denied {
            #expect(checkDenylist(command: command) != .allowed, "\(command) should be denied")
        }
    }

    @Test("Does not over-match ordinary commands and short aliases")
    func allowsOrdinaryCommands() {
        let allowed = [
            "c", "s", "n", "t 1", "v", "p a", "po self", "re read", "process status", "process continue",
            "breakpoint delete", "breakpoint delete 3", "platform status", "platform process list",
            "settings show target.run-args", "settings set target.env-vars A=1", "language swift task tree",
            "target modules list", "memory read 0x1000", "x/4x $sp", "thread backtrace",
        ]
        for command in allowed {
            #expect(checkDenylist(command: command) == .allowed, "\(command) should be allowed")
        }
    }

    @Test("Session protocol rejects quit and auto-confirm changes even when unsafe is allowed")
    func protectsSessionProtocol() {
        for command in [
            "quit", "q", "qu", "exit", "version\nquit",
            "settings set auto-confirm false", "se s auto-confirm 0", "settings clear auto-confirm",
            "settings clear --all", "settings clear -a", "settings read -f /tmp/settings", "sett rea -f x",
        ] {
            #expect(lldbSessionProtocolError(command)?.code == .invalidInput, "\(command) should be rejected")
        }
        for command in ["settings show auto-confirm", "settings set target.env-vars A=1", "breakpoint delete", "version"] {
            #expect(lldbSessionProtocolError(command) == nil, "\(command) should be accepted")
        }
    }
}
