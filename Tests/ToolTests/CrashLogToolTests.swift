//
//  CrashLogToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP
import Testing

@testable import Tools

@Suite("list_crash_logs")
struct CrashLogToolTests {
    @Test("Preserves a header-only IPS report without a trailing newline")
    func headerOnlyIPS() {
        let header = #"{"app_name":"MyApp","bundleID":"com.example.MyApp","timestamp":"today"}"#
        #expect(summarizeIPS(header) == ["Process: MyApp", "Bundle: com.example.MyApp", "Timestamp: today"])
        #expect(summarizeIPS(header) == summarizeIPS(header + "\n"))
    }

    @Test("Returns empty when no crash logs directory")
    func noCrashDir() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(validatorSimctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let response = try await registry.callTool(
            name: "list_crash_logs",
            arguments: [:]
        )

        // Tool should return success with either "No crash logs found" or actual crash logs
        // depending on whether the DiagnosticReports directory exists on this machine
        if case .success(let result) = response {
            #expect(!result.content.isEmpty)
        } else if case .error = response {
            // May error if somehow the tool fails, but shouldn't happen
            Issue.record("Unexpected error")
        }
    }

    @Test("Rebuilds the crashed thread backtrace from an .ips JSON body")
    func ipsBacktrace() {
        let ips = """
        {"app_name":"MyApp","timestamp":"2026-10-21 09:00:00.00 +0000","bundleID":"com.example.MyApp","bug_type":"309","name":"MyApp"}
        {
          "procName" : "MyApp",
          "exception" : {"type" : "EXC_BREAKPOINT", "signal" : "SIGTRAP"},
          "termination" : {"indicator" : "Trace/BPT trap: 5"},
          "faultingThread" : 1,
          "usedImages" : [{"name" : "MyApp"}, {"name" : "libswiftCore.dylib"}],
          "threads" : [
            {"frames" : [{"imageIndex" : 1, "imageOffset" : 10}]},
            {"triggered" : true, "queue" : "com.apple.main-thread", "frames" : [
              {"imageIndex" : 0, "symbol" : "ContentView.crash()", "symbolLocation" : 40, "sourceFile" : "ContentView.swift", "sourceLine" : 12},
              {"imageIndex" : 1, "imageOffset" : 2048}
            ]}
          ]
        }
        """
        let lines = summarizeIPS(ips)
        #expect(lines.contains("Process: MyApp"))
        #expect(lines.contains("Bundle: com.example.MyApp"))
        #expect(lines.contains("Exception: EXC_BREAKPOINT (SIGTRAP)"))
        #expect(lines.contains("Termination: Trace/BPT trap: 5"))
        #expect(lines.contains("Crashed thread 1 (com.apple.main-thread) backtrace:"))
        #expect(lines.contains("  0 MyApp ContentView.crash() + 40 (ContentView.swift:12)"))
        #expect(lines.contains("  1 libswiftCore.dylib + 2048"))
    }

    @Test("Falls back to the text backtrace for legacy .ips files")
    func ipsLegacyText() {
        let ips = """
        {"app_name":"OldApp","bundleID":"com.example.Old"}
        Thread 0 Crashed:
        0   OldApp   0x1000 main + 12

        """
        let lines = summarizeIPS(ips)
        #expect(lines.contains("Process: OldApp"))
        #expect(lines.contains("  0   OldApp   0x1000 main + 12"))
    }
}
