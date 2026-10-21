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
            await session.terminate()
        } catch {
            await session.terminate()
            throw error
        }
    }
}
