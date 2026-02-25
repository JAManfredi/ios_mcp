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
        #expect(tools.count == 65)

        let names = Set(tools.map(\.name))
        #expect(names.contains("discover_projects"))
        #expect(names.contains("list_schemes"))
        #expect(names.contains("show_build_settings"))
        #expect(names.contains("list_simulators"))
        #expect(names.contains("boot_simulator"))
        #expect(names.contains("shutdown_simulator"))
        #expect(names.contains("erase_simulator"))
        #expect(names.contains("session_set_defaults"))
        #expect(names.contains("build_simulator"))
        #expect(names.contains("build_run_simulator"))
        #expect(names.contains("launch_app"))
        #expect(names.contains("stop_app"))
        #expect(names.contains("test_simulator"))
        #expect(names.contains("clean_derived_data"))
        #expect(names.contains("start_log_capture"))
        #expect(names.contains("stop_log_capture"))
        #expect(names.contains("screenshot"))
        #expect(names.contains("deep_link"))
        #expect(names.contains("inspect_ui"))
        #expect(names.contains("tap"))
        #expect(names.contains("swipe"))
        #expect(names.contains("type_text"))
        #expect(names.contains("key_press"))
        #expect(names.contains("long_press"))
        #expect(names.contains("debug_attach"))
        #expect(names.contains("debug_detach"))
        #expect(names.contains("debug_add_breakpoint"))
        #expect(names.contains("debug_remove_breakpoint"))
        #expect(names.contains("debug_resume"))
        #expect(names.contains("debug_backtrace"))
        #expect(names.contains("debug_variables"))
        #expect(names.contains("debug_run_command"))
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
        #expect(names.contains("build_for_device"))
        #expect(names.contains("build_run_device"))
        #expect(names.contains("test_on_device"))
        #expect(names.contains("install_app_device"))
        #expect(names.contains("launch_app_device"))
        #expect(names.contains("stop_app_device"))
        #expect(names.contains("device_screenshot"))
        #expect(names.contains("inspect_xcresult"))
        #expect(names.contains("list_crash_logs"))
        #expect(names.contains("simulate_location"))
        #expect(names.contains("clear_location"))
        #expect(names.contains("set_appearance"))
        #expect(names.contains("override_status_bar"))
        #expect(names.contains("show_session"))
        #expect(names.contains("clear_session"))
        #expect(names.contains("manage_privacy"))
        #expect(names.contains("send_push_notification"))
        #expect(names.contains("get_app_container"))
        #expect(names.contains("uninstall_app"))
    }
}
