//
//  LLDBSessionTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("LLDB command output")
struct LLDBSessionTests {
    @Test("Waits for completion instead of consuming the echoed command prompt")
    func waitsForCompletion() {
        let buffer = LLDBOutputBuffer()
        buffer.append("(lldb) language swift task tree\n")
        #expect(buffer.consumeThroughMarker("# end") == nil)
        buffer.append("error: process must be stopped\n(lldb) # en")
        #expect(buffer.consumeThroughMarker("# end") == nil)
        buffer.append("d\nremaining output")
        #expect(buffer.consumeThroughMarker("# end") == "(lldb) language swift task tree\nerror: process must be stopped\n")
        #expect(buffer.drain() == "remaining output")
    }

    @Test("Captures real LLDB stderr and keeps consecutive replies separate")
    func capturesDiagnostics() async throws {
        // Only query the debugger itself; no application is launched or attached.
        let session = LLDBSession(id: UUID().uuidString)
        try await session.launch()
        do {
            let output = try await session.sendCommand("__ios_mcp_missing_command__", timeout: 10)
            #expect(output.contains("error:"))
            #expect(output.contains("not a valid command"))
            #expect(!output.contains("(lldb)"))
            #expect(!output.contains("ios-mcp-command-end"))

            let version = try await session.sendCommand("version", timeout: 10)
            #expect(version.contains("lldb-"))
            #expect(!version.contains("__ios_mcp_missing_command__"))
            #expect(!version.contains("error:"))

            // Load symbols only. LLDB 27 crashes deleting IDs on its dummy target.
            _ = try await session.sendCommand("target create /usr/bin/true", timeout: 10)
            _ = try await session.sendCommand("breakpoint set --name ios_mcp_pending", timeout: 10)
            for command in ["quit", "q", "exit", "breakpoint delete\nversion", "settings set auto-confirm false", "se s auto-confirm 0", "settings clear --all", "settings read -f /dev/null"] {
                do {
                    _ = try await session.sendCommand(command, timeout: 1)
                    Issue.record("Expected an actionable noninteractive-command error")
                } catch let error as ToolError {
                    #expect(error.code == .invalidInput)
                }
            }
            let listing = try await session.sendCommand("breakpoint list", timeout: 10)
            #expect(listing.contains("ios_mcp_pending"))
            #expect(try await session.sendCommand("settings show auto-confirm", timeout: 10).contains("auto-confirm (boolean) = true"))
            let deleted = try await session.sendCommand("breakpoint delete 1", timeout: 10)
            #expect(deleted.contains("deleted"))
            #expect(try await session.sendCommand("version", timeout: 10).contains("lldb-"))
            await session.terminate()
        } catch {
            await session.terminate()
            throw error
        }
    }

    @Test("Attached sessions keep auto-confirm and stay usable after denied commands")
    func attachedSessionSurvivesDeniedCommands() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ios-mcp-lldb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // System binaries use the hardened runtime and can't be attached, so
        // build a plain one. clang signs it ad hoc without the hardened runtime.
        let source = directory.appendingPathComponent("spin.c")
        let binary = directory.appendingPathComponent("spin")
        try "#include <unistd.h>\nint main(void) { for (;;) sleep(1); }\n".write(to: source, atomically: true, encoding: .utf8)
        let compile = try await CommandExecutor().execute(
            executable: "/usr/bin/xcrun",
            arguments: ["clang", "-o", binary.path, source.path],
            timeout: 60,
            environment: nil
        )
        try #require(compile.succeeded, "clang failed: \(compile.stderr)")

        let target = Process()
        target.executableURL = binary
        target.standardInput = FileHandle.nullDevice
        try target.run()
        defer { target.terminate() }
        let pid = target.processIdentifier

        let manager = LLDBSessionManager()
        let sessionID = try await manager.attach(pid: Int(pid), bundleID: nil, udid: nil)
        do {
            func run(_ command: String) async throws -> String {
                try await manager.sendCommand(sessionID: sessionID, command: command, timeout: 10)
            }
            func expectAttached() async throws {
                let status = try await run("process status")
                #expect(status.contains("Process \(pid) stopped"), "\(status)")
            }

            #expect(try await run("settings show auto-confirm").contains("auto-confirm (boolean) = true"))
            try await expectAttached()

            // Each of these would prompt while attached, and the default answer
            // kills, relaunches, or replaces the target.
            for command in [
                "r", "run", "ru", "process launch", "pro la", "attach \(pid)", "att \(pid)", "process attach --pid \(pid)",
                "proc a -p \(pid)", "process connect connect://localhost:1", "gdb-remote 1", "kill", "ki",
                "platform process launch /usr/bin/true", "command alias relaunch process launch",
            ] {
                #expect(checkDenylist(command: command) != .allowed, "\(command) should be denied")
            }

            for command in ["settings set auto-confirm false", "se s auto-confirm 0", "settings clear --all", "settings read -f /dev/null", "quit", "q"] {
                do {
                    _ = try await run(command)
                    Issue.record("Expected \(command) to be rejected")
                } catch let error as ToolError {
                    #expect(error.code == .invalidInput)
                }
                try await expectAttached()
            }

            // Bulk deletion prompts; auto-confirm answers it so the reply
            // completes instead of consuming the completion marker.
            _ = try await run("breakpoint set --name ios_mcp_pending")
            let deleted = try await run("breakpoint delete")
            #expect(deleted.contains("removed"), "\(deleted)")
            try await expectAttached()
            #expect(try await run("settings show auto-confirm").contains("auto-confirm (boolean) = true"))

            try await manager.detach(sessionID: sessionID)
        } catch {
            try? await manager.detach(sessionID: sessionID)
            throw error
        }
    }
}
