# E2E Testing — New Features

Manual end-to-end testing for features added in the feature-gap closure release. Each section lists the tool, sample input, expected output, and a pass/fail checkbox.

## Prerequisites

- macOS Sonoma or later
- Xcode 16.0+
- A booted iOS simulator (`xcrun simctl boot <UDID>`)
- A sample Xcode project with a Swift package (e.g., this repo itself)
- **For Device tests**: A connected physical iOS device with valid provisioning
- `swift`, `xcrun`, `simctl`, `devicectl` available in PATH

---

## 1. Swift Package Tools

### swift_package_resolve

- **Input**: `{ "path": "/path/to/ios-mcp" }`
- **Expected**: Output contains "Resolved" or "Fetching" messages, exits successfully
- [ ] Pass

### swift_package_update

- **Input**: `{ "path": "/path/to/ios-mcp" }`
- **Expected**: Output contains package update activity, exits successfully
- [ ] Pass

### swift_package_init

- **Input**: `{ "path": "/tmp/test-pkg", "type": "library", "name": "TestLib" }`
- **Expected**: Creates Package.swift and Sources/ directory at the specified path
- [ ] Pass

### swift_package_clean

- **Input**: `{ "path": "/path/to/ios-mcp" }`
- **Expected**: Output confirms .build directory cleaned
- [ ] Pass

### swift_package_show_deps

- **Input**: `{ "path": "/path/to/ios-mcp" }`
- **Expected**: JSON output listing package dependencies with name, url, version
- [ ] Pass

### swift_package_dump

- **Input**: `{ "path": "/path/to/ios-mcp" }`
- **Expected**: JSON output of full Package.swift manifest (targets, products, dependencies)
- [ ] Pass

---

## 2. Video Recording

### start_recording

- **Input**: `{ "udid": "<booted-sim-udid>" }`
- **Expected**: Returns a session ID string (UUID format)
- [ ] Pass

### stop_recording

- **Input**: `{ "session_id": "<session-id-from-start>" }`
- **Expected**: Returns artifact reference with path to a valid MP4 file, file size > 0
- **Verify**: Open the MP4 — it should play without corruption (SIGINT finalization worked)
- [ ] Pass

### Full workflow

1. `start_recording` on booted simulator
2. Interact with the simulator (tap, swipe, navigate)
3. `stop_recording`
4. Verify MP4 plays correctly in QuickTime
- [ ] Pass

---

## 3. Device Builds

> Requires a connected physical iOS device with valid code signing.

### list_devices

- **Input**: `{}`
- **Expected**: JSON listing connected devices with UDID, name, OS version. Auto-sets session `device_udid` if exactly one device connected.
- [ ] Pass

### list_devices (no device)

- **Input**: `{}` (with no device connected)
- **Expected**: Returns empty device list or informative message, no crash
- [ ] Pass

### build_device

- **Input**: `{ "workspace": "<path>", "scheme": "<scheme>" }`
- **Expected**: Build succeeds with device destination, returns error/warning counts and xcresult path
- [ ] Pass

### build_run_device

- **Input**: `{ "workspace": "<path>", "scheme": "<scheme>" }`
- **Expected**: Builds, installs via `devicectl device install app`, launches via `devicectl device process launch`. App visible on device.
- [ ] Pass

### test_device

- **Input**: `{ "workspace": "<path>", "scheme": "<scheme>" }`
- **Expected**: Tests run on physical device, returns pass/fail/skip counts
- [ ] Pass

### install_app_device

- **Input**: `{ "app_path": "<path-to-.app>" }`
- **Expected**: App installed on device successfully
- [ ] Pass

### launch_app_device

- **Input**: `{ "bundle_id": "<bundle-id>" }`
- **Expected**: App launches on device
- [ ] Pass

### stop_app_device

- **Input**: `{ "bundle_id": "<bundle-id>" }`
- **Expected**: App terminated on device (or graceful message if termination not supported)
- [ ] Pass

### device_screenshot

- **Input**: `{}`
- **Expected**: Returns artifact reference to PNG screenshot from physical device
- [ ] Pass

---

## 4. XCResult Inspection

### Setup

Run `build_sim` or `test_sim` first to generate an `.xcresult` bundle. Note the xcresult path from the output.

### inspect_xcresult — diagnostics

- **Input**: `{ "path": "<xcresult-path>", "sections": "diagnostics" }`
- **Expected**: Lists build errors/warnings with file paths and line numbers
- [ ] Pass

### inspect_xcresult — tests

- **Input**: `{ "path": "<xcresult-path>", "sections": "tests" }`
- **Expected**: Lists test results with per-test duration and pass/fail status
- [ ] Pass

### inspect_xcresult — coverage

- **Input**: `{ "path": "<xcresult-path>", "sections": "coverage" }`
- **Expected**: Line coverage percentages per target/file
- [ ] Pass

### inspect_xcresult — attachments

- **Input**: `{ "path": "<xcresult-path>", "sections": "attachments" }`
- **Expected**: Exports UI test failure screenshots to ArtifactStore (if any exist), or reports none found
- [ ] Pass

### inspect_xcresult — timeline

- **Input**: `{ "path": "<xcresult-path>", "sections": "timeline" }`
- **Expected**: Per-target build durations, total wall time
- [ ] Pass

### inspect_xcresult — all sections

- **Input**: `{ "path": "<xcresult-path>" }`
- **Expected**: Combined output of all 5 sections above
- [ ] Pass

---

## 5. Crash Log Analysis

### Setup

1. Build and run an app on the simulator that triggers a crash (e.g., force unwrap nil, array out of bounds)
2. Wait for the crash report to appear in `~/Library/Logs/DiagnosticReports/`

### list_crash_logs

- **Input**: `{ "limit": 5 }`
- **Expected**: Lists up to 5 most recent crash logs with timestamp, process name, exception type, and crashed thread backtrace
- [ ] Pass

### list_crash_logs — filtered by bundle_id

- **Input**: `{ "bundle_id": "<crashed-app-bundle-id>", "limit": 3 }`
- **Expected**: Only crash logs matching the bundle ID are returned
- [ ] Pass

### list_crash_logs — no crashes

- **Input**: `{ "bundle_id": "com.nonexistent.app" }`
- **Expected**: Returns "No crash logs found" message, no error
- [ ] Pass

---

## 6. Homebrew

### Build from source

```bash
brew install --build-from-source Formula/ios-mcp.rb
```

- **Expected**: Builds successfully, installs `ios-mcp` binary
- [ ] Pass

### Verify binary

```bash
ios-mcp --version
ios-mcp doctor
```

- **Expected**: Version string printed, doctor reports tool availability
- [ ] Pass

### Makefile

```bash
make build && make install PREFIX=/tmp/ios-mcp-test
```

- **Expected**: Binary built and copied to `/tmp/ios-mcp-test/bin/ios-mcp`
- [ ] Pass
