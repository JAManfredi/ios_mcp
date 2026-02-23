# End-to-End Test Checklist

Test against Jarvis project (`/Users/jared/workspace/iOS/Jarvis`) with iOS 26.2 simulator (iPhone 17 Pro).

## Project Discovery (3 tools)
- [x] `discover_projects` — finds Jarvis.xcodeproj, auto-sets session project
- [x] `list_schemes` — returns Jarvis, ItemCollection, Textual schemes
- [x] `show_build_settings` — returns curated settings, auto-sets bundle_id

## Simulator Management (5 tools)
- [x] `list_simulators` — lists 74 simulators grouped by runtime
- [x] `boot_simulator` — boots iPhone 17 Pro (iOS 26.2)
- [x] `shutdown_simulator` — shuts down booted simulator
- [ ] `erase_simulator` — erases a shutdown simulator
- [x] `session_set_defaults` — sets scheme + UDID

## Build & Run (6 tools)
- [x] `build_sim` — builds Jarvis (87s, 0 errors)
- [ ] `build_run_sim` — builds, installs, launches on simulator
- [ ] `test_sim` — runs JarvisTests, returns pass/fail counts
- [ ] `launch_app` — launches already-built app
- [ ] `stop_app` — terminates running app
- [ ] `clean_derived_data` — removes DerivedData

## Logging (2 tools)
- [ ] `start_log_capture` — starts capture, returns session_id
- [ ] `stop_log_capture` — stops capture, returns entries

## UI Automation (8 tools) — axe blocked on x86_64
- [ ] `screenshot` — captures simulator screen (no axe needed)
- [ ] `snapshot_ui` — accessibility tree (requires axe)
- [ ] `deep_link` — opens URL in simulator (no axe needed)
- [ ] `tap` — taps element (requires axe)
- [ ] `swipe` — swipes on element (requires axe)
- [ ] `type_text` — types into field (requires axe)
- [ ] `key_press` — sends key event (requires axe)
- [ ] `long_press` — long presses element (requires axe)

## Debugging (8 tools)
- [ ] `debug_attach` — attaches LLDB to running app
- [ ] `debug_breakpoint_add` — adds breakpoint
- [ ] `debug_continue` — resumes execution
- [ ] `debug_stack` — returns backtrace
- [ ] `debug_variables` — returns frame variables
- [ ] `debug_breakpoint_remove` — removes breakpoint
- [ ] `debug_lldb_command` — executes LLDB command
- [ ] `debug_detach` — detaches and cleans up

## Inspection (2 tools)
- [ ] `read_user_defaults` — reads app defaults
- [ ] `write_user_default` — writes a default value

## Quality (2 tools)
- [ ] `lint` — runs SwiftLint on project
- [ ] `accessibility_audit` — accessibility check (requires axe)

## Extras (1 tool)
- [ ] `open_simulator` — opens Simulator.app

## Error Paths
- [x] `build_sim` wrong runtime — fails (now improved with stderr)
- [ ] `build_sim` lock held — returns resource_busy
- [ ] Tool with stale UDID — returns stale_default
- [ ] `debug_lldb_command` denied command — returns command_denied
