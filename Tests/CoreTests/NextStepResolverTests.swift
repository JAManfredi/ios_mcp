//
//  NextStepResolverTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("NextStepResolver")
struct NextStepResolverTests {

    @Test("Resolves build_sim next steps")
    func resolvesBuildSimNextSteps() {
        let steps = NextStepResolver.resolve(for: "build_sim")
        #expect(steps.count == 3)
        #expect(steps[0].tool == "build_run_sim")
        #expect(steps[1].tool == "test_sim")
        #expect(steps[2].tool == "launch_app")
    }

    @Test("Resolves discover_projects next steps")
    func resolvesDiscoverProjectsNextSteps() {
        let steps = NextStepResolver.resolve(for: "discover_projects")
        #expect(steps.count == 2)
        #expect(steps[0].tool == "list_schemes")
        #expect(steps[1].tool == "session_set_defaults")
    }

    @Test("Unknown tool returns empty array")
    func unknownToolReturnsEmpty() {
        let steps = NextStepResolver.resolve(for: "nonexistent_tool")
        #expect(steps.isEmpty)
    }

    @Test("All 37 registered tools have next steps")
    func allRegisteredToolsHaveNextSteps() {
        let allToolNames: Set<String> = [
            "discover_projects", "list_schemes", "show_build_settings",
            "list_simulators", "boot_simulator", "shutdown_simulator",
            "erase_simulator", "session_set_defaults",
            "build_sim", "build_run_sim", "test_sim",
            "launch_app", "stop_app", "clean_derived_data",
            "screenshot", "snapshot_ui", "deep_link",
            "tap", "swipe", "type_text", "key_press", "long_press",
            "start_log_capture", "stop_log_capture",
            "debug_attach", "debug_detach",
            "debug_breakpoint_add", "debug_breakpoint_remove",
            "debug_continue", "debug_stack", "debug_variables",
            "debug_lldb_command",
            "read_user_defaults", "write_user_default",
            "accessibility_audit", "lint",
            "open_simulator",
        ]

        for toolName in allToolNames {
            let steps = NextStepResolver.resolve(for: toolName)
            #expect(!steps.isEmpty, "Tool '\(toolName)' should have at least one next step")
        }
    }
}
