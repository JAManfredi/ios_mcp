//
//  ToolRegistrationTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("Tool Registration")
struct ToolRegistrationTests {
    @Test("Registers all tools")
    func registerAll() async {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording())

        let tools = await registry.listTools()
        #expect(tools.count == 55)

        let names = Set(tools.map(\.name))
        #expect(names.contains("discover_projects"))
        #expect(names.contains("list_schemes"))
        #expect(names.contains("show_build_settings"))
        #expect(names.contains("list_simulators"))
        #expect(names.contains("boot_simulator"))
        #expect(names.contains("shutdown_simulator"))
        #expect(names.contains("erase_simulator"))
        #expect(names.contains("session_set_defaults"))
        #expect(names.contains("build_sim"))
        #expect(names.contains("build_run_sim"))
        #expect(names.contains("launch_app"))
        #expect(names.contains("stop_app"))
        #expect(names.contains("test_sim"))
        #expect(names.contains("clean_derived_data"))
        #expect(names.contains("start_log_capture"))
        #expect(names.contains("stop_log_capture"))
        #expect(names.contains("screenshot"))
        #expect(names.contains("deep_link"))
        #expect(names.contains("snapshot_ui"))
        #expect(names.contains("tap"))
        #expect(names.contains("swipe"))
        #expect(names.contains("type_text"))
        #expect(names.contains("key_press"))
        #expect(names.contains("long_press"))
        #expect(names.contains("debug_attach"))
        #expect(names.contains("debug_detach"))
        #expect(names.contains("debug_breakpoint_add"))
        #expect(names.contains("debug_breakpoint_remove"))
        #expect(names.contains("debug_continue"))
        #expect(names.contains("debug_stack"))
        #expect(names.contains("debug_variables"))
        #expect(names.contains("debug_lldb_command"))
        #expect(names.contains("read_user_defaults"))
        #expect(names.contains("write_user_default"))
        #expect(names.contains("lint"))
        #expect(names.contains("accessibility_audit"))
        #expect(names.contains("open_simulator"))
        #expect(names.contains("swift_package_resolve"))
        #expect(names.contains("swift_package_update"))
        #expect(names.contains("swift_package_init"))
        #expect(names.contains("swift_package_clean"))
        #expect(names.contains("swift_package_show_deps"))
        #expect(names.contains("swift_package_dump"))
        #expect(names.contains("start_recording"))
        #expect(names.contains("stop_recording"))
        #expect(names.contains("list_devices"))
        #expect(names.contains("build_device"))
        #expect(names.contains("build_run_device"))
        #expect(names.contains("test_device"))
        #expect(names.contains("install_app_device"))
        #expect(names.contains("launch_app_device"))
        #expect(names.contains("stop_app_device"))
        #expect(names.contains("device_screenshot"))
        #expect(names.contains("inspect_xcresult"))
        #expect(names.contains("list_crash_logs"))
    }
}
