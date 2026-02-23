//
//  NextStepResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Resolves suggested next steps for a given tool name based on natural workflow progression.
public struct NextStepResolver: Sendable {

    private static let mapping: [String: [NextStep]] = [
        // Project Discovery
        "discover_projects": [
            NextStep(tool: "list_schemes", description: "List available schemes for a discovered project"),
            NextStep(tool: "session_set_defaults", description: "Set workspace/project as session default"),
        ],
        "list_schemes": [
            NextStep(tool: "session_set_defaults", description: "Set scheme as session default"),
            NextStep(tool: "build_sim", description: "Build the project for simulator"),
        ],
        "show_build_settings": [
            NextStep(tool: "build_sim", description: "Build the project for simulator"),
            NextStep(tool: "session_set_defaults", description: "Update session defaults based on settings"),
        ],

        // Simulator Management
        "list_simulators": [
            NextStep(tool: "session_set_defaults", description: "Set simulator UDID as session default"),
            NextStep(tool: "boot_simulator", description: "Boot a simulator device"),
        ],
        "boot_simulator": [
            NextStep(tool: "build_sim", description: "Build an app for the booted simulator"),
            NextStep(tool: "launch_app", description: "Launch an already-built app"),
            NextStep(tool: "screenshot", description: "Take a screenshot of the simulator"),
        ],
        "shutdown_simulator": [
            NextStep(tool: "boot_simulator", description: "Boot a different simulator"),
            NextStep(tool: "list_simulators", description: "List available simulators"),
        ],
        "erase_simulator": [
            NextStep(tool: "boot_simulator", description: "Boot the erased simulator"),
        ],
        "session_set_defaults": [
            NextStep(tool: "build_sim", description: "Build the project with updated defaults"),
            NextStep(tool: "list_simulators", description: "List available simulators"),
        ],

        // Build & Run
        "build_sim": [
            NextStep(tool: "build_run_sim", description: "Build and run the app on simulator"),
            NextStep(tool: "test_sim", description: "Run tests on simulator"),
            NextStep(tool: "launch_app", description: "Launch the built app"),
        ],
        "build_run_sim": [
            NextStep(tool: "screenshot", description: "Take a screenshot of the running app"),
            NextStep(tool: "snapshot_ui", description: "Capture the accessibility tree"),
            NextStep(tool: "start_log_capture", description: "Start capturing app logs"),
            NextStep(tool: "debug_attach", description: "Attach debugger to the running app"),
        ],
        "test_sim": [
            NextStep(tool: "build_sim", description: "Rebuild after fixing test failures"),
            NextStep(tool: "lint", description: "Run linter on the project"),
        ],
        "launch_app": [
            NextStep(tool: "screenshot", description: "Take a screenshot of the running app"),
            NextStep(tool: "snapshot_ui", description: "Capture the accessibility tree"),
            NextStep(tool: "start_log_capture", description: "Start capturing app logs"),
            NextStep(tool: "debug_attach", description: "Attach debugger to the running app"),
        ],
        "stop_app": [
            NextStep(tool: "launch_app", description: "Relaunch the app"),
            NextStep(tool: "build_sim", description: "Rebuild the app"),
        ],
        "clean_derived_data": [
            NextStep(tool: "build_sim", description: "Rebuild from clean state"),
        ],

        // UI Automation
        "screenshot": [
            NextStep(tool: "snapshot_ui", description: "Capture the accessibility tree for element inspection"),
            NextStep(tool: "tap", description: "Tap a UI element"),
        ],
        "snapshot_ui": [
            NextStep(tool: "tap", description: "Tap an element by coordinate or identifier"),
            NextStep(tool: "type_text", description: "Type text into a focused field"),
            NextStep(tool: "swipe", description: "Swipe on the screen"),
            NextStep(tool: "screenshot", description: "Take a screenshot for visual verification"),
        ],
        "deep_link": [
            NextStep(tool: "screenshot", description: "Take a screenshot after navigation"),
            NextStep(tool: "snapshot_ui", description: "Capture the accessibility tree after navigation"),
        ],
        "tap": [
            NextStep(tool: "snapshot_ui", description: "Capture UI state after tap"),
            NextStep(tool: "screenshot", description: "Take a screenshot after tap"),
            NextStep(tool: "type_text", description: "Type text into the tapped field"),
        ],
        "swipe": [
            NextStep(tool: "snapshot_ui", description: "Capture UI state after swipe"),
            NextStep(tool: "screenshot", description: "Take a screenshot after swipe"),
        ],
        "type_text": [
            NextStep(tool: "snapshot_ui", description: "Capture UI state after typing"),
            NextStep(tool: "screenshot", description: "Take a screenshot after typing"),
            NextStep(tool: "tap", description: "Tap another element"),
        ],
        "key_press": [
            NextStep(tool: "snapshot_ui", description: "Capture UI state after key press"),
            NextStep(tool: "screenshot", description: "Take a screenshot after key press"),
        ],
        "long_press": [
            NextStep(tool: "snapshot_ui", description: "Capture UI state after long press"),
            NextStep(tool: "screenshot", description: "Take a screenshot after long press"),
        ],

        // Logging
        "start_log_capture": [
            NextStep(tool: "stop_log_capture", description: "Stop capture and retrieve logs"),
        ],
        "stop_log_capture": [
            NextStep(tool: "start_log_capture", description: "Start a new log capture session"),
        ],

        // Debugging
        "debug_attach": [
            NextStep(tool: "debug_breakpoint_add", description: "Set a breakpoint"),
            NextStep(tool: "debug_stack", description: "View the call stack"),
            NextStep(tool: "debug_variables", description: "Inspect frame variables"),
        ],
        "debug_detach": [
            NextStep(tool: "debug_attach", description: "Reattach to the process"),
            NextStep(tool: "stop_app", description: "Stop the app"),
        ],
        "debug_breakpoint_add": [
            NextStep(tool: "debug_continue", description: "Continue execution to hit the breakpoint"),
            NextStep(tool: "debug_breakpoint_remove", description: "Remove a breakpoint"),
        ],
        "debug_breakpoint_remove": [
            NextStep(tool: "debug_breakpoint_add", description: "Add a different breakpoint"),
            NextStep(tool: "debug_continue", description: "Continue execution"),
        ],
        "debug_continue": [
            NextStep(tool: "debug_stack", description: "View the call stack"),
            NextStep(tool: "debug_variables", description: "Inspect frame variables"),
            NextStep(tool: "debug_detach", description: "Detach the debugger"),
        ],
        "debug_stack": [
            NextStep(tool: "debug_variables", description: "Inspect variables in the current frame"),
            NextStep(tool: "debug_lldb_command", description: "Run a custom LLDB command"),
        ],
        "debug_variables": [
            NextStep(tool: "debug_lldb_command", description: "Run a custom LLDB command for deeper inspection"),
            NextStep(tool: "debug_continue", description: "Continue execution"),
        ],
        "debug_lldb_command": [
            NextStep(tool: "debug_variables", description: "Inspect frame variables"),
            NextStep(tool: "debug_continue", description: "Continue execution"),
        ],

        // Inspection
        "read_user_defaults": [
            NextStep(tool: "write_user_default", description: "Write a user default value"),
        ],
        "write_user_default": [
            NextStep(tool: "read_user_defaults", description: "Verify the written value"),
        ],

        // Quality
        "accessibility_audit": [
            NextStep(tool: "snapshot_ui", description: "Inspect the accessibility tree for details"),
            NextStep(tool: "screenshot", description: "Take a screenshot for context"),
        ],
        "lint": [
            NextStep(tool: "build_sim", description: "Build after fixing lint issues"),
        ],

        // Extras
        "open_simulator": [
            NextStep(tool: "screenshot", description: "Take a screenshot of the visible simulator"),
        ],
    ]

    /// Returns the suggested next steps for a tool, or an empty array if unknown.
    public static func resolve(for toolName: String) -> [NextStep] {
        mapping[toolName] ?? []
    }

    /// All tool names that have next-step mappings.
    public static var registeredToolNames: Set<String> {
        Set(mapping.keys)
    }
}
