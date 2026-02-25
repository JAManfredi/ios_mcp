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
        #expect(steps.count == 4)
        #expect(steps[0].tool == "build_run_sim")
        #expect(steps[1].tool == "test_sim")
        #expect(steps[2].tool == "launch_app")
        #expect(steps[3].tool == "inspect_xcresult")
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

    @Test("Session-aware resolve populates simulator UDID context")
    func sessionAwareResolvesSimulatorContext() async {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "UDID-1234")

        let steps = await NextStepResolver.resolve(for: "boot_simulator", session: session)
        #expect(steps.count == 3)
        #expect(steps[0].context["simulator_udid"] == "UDID-1234")
        #expect(steps[0].tool == "build_sim")
    }

    @Test("Session-aware resolve populates workspace and scheme context")
    func sessionAwareResolvesWorkspaceContext() async {
        let session = SessionStore()
        await session.set(.workspace, value: "/path/to/App.xcworkspace")
        await session.set(.scheme, value: "App")
        await session.set(.simulatorUDID, value: "SIM-1")

        let steps = await NextStepResolver.resolve(for: "list_schemes", session: session)
        #expect(steps.count == 2)
        // session_set_defaults doesn't need workspace context
        // build_sim needs workspace + scheme + simulator
        let buildStep = steps.first { $0.tool == "build_sim" }!
        #expect(buildStep.context["workspace"] == "/path/to/App.xcworkspace")
        #expect(buildStep.context["scheme"] == "App")
        #expect(buildStep.context["simulator_udid"] == "SIM-1")
    }

    @Test("Session-aware resolve returns empty context when no defaults set")
    func sessionAwareEmptySessionReturnsNoContext() async {
        let session = SessionStore()
        let steps = await NextStepResolver.resolve(for: "build_sim", session: session)
        #expect(steps.count == 4)
        #expect(steps[0].context.isEmpty)
    }

    @Test("Session-aware resolve unknown tool returns empty")
    func sessionAwareUnknownToolReturnsEmpty() async {
        let session = SessionStore()
        let steps = await NextStepResolver.resolve(for: "nonexistent", session: session)
        #expect(steps.isEmpty)
    }

    @Test("All registered tools have next steps")
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
            "swift_package_resolve", "swift_package_update",
            "swift_package_init", "swift_package_clean",
            "swift_package_show_deps", "swift_package_dump",
            "start_recording", "stop_recording",
            "list_devices", "build_device", "build_run_device",
            "test_device", "install_app_device", "launch_app_device",
            "stop_app_device", "device_screenshot",
            "inspect_xcresult",
            "list_crash_logs",
        ]

        for toolName in allToolNames {
            let steps = NextStepResolver.resolve(for: toolName)
            #expect(!steps.isEmpty, "Tool '\(toolName)' should have at least one next step")
        }
    }
}
