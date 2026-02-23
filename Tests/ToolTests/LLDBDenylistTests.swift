//
//  LLDBDenylistTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Tools

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
}
