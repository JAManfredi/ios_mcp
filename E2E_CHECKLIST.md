# End-to-End Test Checklist

Test against Jarvis project (`/Users/jared/workspace/iOS/Jarvis`) with iOS 26.2 simulator (iPhone 17 Pro).

## Project Discovery (3 tools)
- [x] `discover_projects` — finds Jarvis.xcodeproj, auto-sets session project
- [x] `list_schemes` — returns Jarvis, ItemCollection, Textual schemes
- [x] `show_build_settings` — returns curated settings, auto-sets bundle_id + deployment_target

## Simulator Management (5 tools)
- [x] `list_simulators` — lists 74 simulators grouped by runtime, shows deployment target hints
- [x] `boot_simulator` — boots iPhone 17 Pro (iOS 26.2)
- [x] `shutdown_simulator` — shuts down booted simulator
- [x] `erase_simulator` — erases a shutdown simulator (confirm guard works)
- [x] `session_set_defaults` — sets scheme + UDID

## Build & Run (6 tools)
- [x] `build_sim` — builds Jarvis (87s, 0 errors)
- [x] `build_run_sim` — builds, installs, launches (21s total). Fixed -destination in -showBuildSettings.
- [x] `test_sim` — runs tests, returns pass/fail counts (0 tests in Jarvis scheme)
- [x] `launch_app` — launches already-built app
- [x] `stop_app` — terminates running app
- [x] `clean_derived_data` — removes DerivedData (confirm guard works)

## Logging (2 tools)
- [x] `start_log_capture` — starts capture, returns session_id
- [x] `stop_log_capture` — stops capture, returns entries (0 for idle app)

## UI Automation (8 tools) — axe blocked on x86_64
- [x] `screenshot` — captures simulator screen
- [ ] `snapshot_ui` — accessibility tree (requires axe)
- [x] `deep_link` — opens URL in simulator
- [ ] `tap` — taps element (requires axe)
- [ ] `swipe` — swipes on element (requires axe)
- [ ] `type_text` — types into field (requires axe)
- [ ] `key_press` — sends key event (requires axe)
- [ ] `long_press` — long presses element (requires axe)

## Debugging (8 tools)
- [x] `debug_attach` — attaches LLDB to running app. Fixed actor deadlock + removed --waitfor.
- [x] `debug_breakpoint_add` — adds breakpoint by symbol (e.g. viewDidLoad)
- [x] `debug_continue` — resumes execution, reports stop reason
- [x] `debug_stack` — returns backtrace with frame details
- [x] `debug_variables` — returns frame variables with types and values
- [x] `debug_breakpoint_remove` — removes breakpoint by ID
- [x] `debug_lldb_command` — executes arbitrary LLDB command (e.g. thread info)
- [x] `debug_detach` — detaches and cleans up LLDB process

## Inspection (2 tools)
- [x] `read_user_defaults` — reads app defaults
- [x] `write_user_default` — writes a default value

## Quality (2 tools)
- [x] `lint` — returns full JSON violations. Fixed --path → positional arg + exit code 2 threshold.
- [ ] `accessibility_audit` — accessibility check (requires axe)

## Extras (1 tool)
- [x] `open_simulator` — opens Simulator.app

## Error Paths
- [x] `build_sim` wrong runtime — fails (now improved with stderr)
- [ ] `build_sim` lock held — returns resource_busy
- [ ] Tool with stale UDID — returns stale_default
- [x] `debug_lldb_command` denied command — returns command_denied (tested `process kill`)

## Bugs Found & Fixed
1. `build_run_sim` — `-showBuildSettings` missing `-destination`, resolved to iphoneos path instead of iphonesimulator
2. `lint` — SwiftLint dropped `--path` flag, now uses positional argument
3. `lint` — exit code 2 (error-severity violations) incorrectly treated as fatal, changed threshold to >= 3
4. `debug_attach` — actor deadlock: `waitForPrompt` spin loop held actor while readTask needed actor isolation. Fixed with NSLock-based `LLDBOutputBuffer`.
5. `debug_attach` — `--waitfor` flag waits for next process launch, not current. Removed flag.
