<p align="center">
  <img src="assets/banner.svg" alt="ios-mcp — headless iOS dev, straight from the CLI" width="700">
</p>

<p align="center">
  <a href="https://modelcontextprotocol.io/"><img src="https://img.shields.io/badge/MCP-Compatible-blue?style=flat-square" alt="MCP Compatible"></a>
  <a href="https://github.com/apple/swift"><img src="https://img.shields.io/badge/Swift-6.1+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.1+"></a>
  <a href="https://developer.apple.com/xcode/"><img src="https://img.shields.io/badge/Xcode-16–27-147EFB?style=flat-square&logo=xcode&logoColor=white" alt="Xcode 16 to 27"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  An <a href="https://modelcontextprotocol.io/">MCP</a> server for the iOS development lifecycle — <b>76 tools</b> for project discovery, simulator &amp; device management, building, testing, UI automation, debugging, navigation, package management, and quality checks. Works with any MCP-compatible client.
</p>

---

## 💡 Why ios-mcp

- **Single native binary** — one `make install` and you're running. No runtimes, no interpreters, no background daemons. Optional tools (axe, SwiftLint) enhance specific features but aren't required.
- **Interactive debugging** — attach to processes, set breakpoints, inspect stacks and variables, execute LLDB commands — all through MCP. Go beyond build-and-test into real debugging workflows.
- **Deep UI automation** — tap, swipe, type, long press, screenshot, record video, read the full accessibility tree. Drive the simulator the way a user would.
- **Security by default** — secrets are automatically redacted from all output (tokens, keys, signing identities). Dangerous debugger commands are blocked. All subprocesses use argument arrays — never shell execution. No telemetry. No network access.
- **Post-mortem analysis** — parse crash logs with symbolicated backtraces, inspect xcresult bundles for diagnostics, test failures, code coverage, and build timelines. Understand *what went wrong* without leaving the terminal.
- **Session intelligence** — tools auto-discover context (workspace, scheme, simulator, device) and validate it before use. Stale defaults are caught, not silently reused. Every response includes suggested next steps for natural workflow progression.
- **Graph-based navigation** — load a navigation graph describing your app's screens and transitions, then navigate deterministically via BFS pathfinding. Supports deeplinks, taps, swipes, text input, and key presses. Works without a graph too — tools gracefully fall back to direct UI automation.
- **Full lifecycle coverage** — 76 tools spanning project discovery, simulator and device management, building, testing, UI automation, debugging, navigation, logging, Swift packages, crash analysis, and quality checks.

---

## ⚡ Quick Start

```bash
# Install
git clone https://github.com/JAManfredi/ios_mcp.git && cd ios_mcp
make install

# Verify
ios-mcp doctor
```

---

## 🛠 What's Included

**76 tools** across **13 categories**:

| Category | Count | Tools |
|----------|:-----:|-------|
| 🔍 **Project Discovery** | 3 | `discover_projects` · `list_schemes` · `show_build_settings` |
| 📱 **Simulator** | 17 | `list_simulators` · `boot_simulator` · `shutdown_simulator` · `erase_simulator` · `reboot_simulator` · `set_orientation` · `session_set_defaults` · `simulate_location` · `clear_location` · `set_appearance` · `override_status_bar` · `show_session` · `clear_session` · `manage_privacy` · `send_push_notification` · `get_app_container` · `uninstall_app` |
| 🔨 **Build** | 8 | `build_simulator` · `build_run_simulator` · `test_simulator` · `launch_app` · `stop_app` · `clean_derived_data` · `inspect_xcresult` · `list_crash_logs` |
| 📲 **Device** | 9 | `list_devices` · `build_for_device` · `build_run_device` · `test_on_device` · `install_app_device` · `launch_app_device` · `stop_app_device` · `device_screenshot` · `record_device_screen` |
| 📋 **Logging** | 2 | `start_log_capture` · `stop_log_capture` |
| 👆 **UI Automation** | 10 | `screenshot` · `inspect_ui` · `deep_link` · `tap` · `swipe` · `type_text` · `key_press` · `long_press` · `start_recording` · `stop_recording` |
| 🧭 **Navigation** | 6 | `load_nav_graph` · `get_nav_graph` · `navigate_to` · `where_am_i` · `tag_screen` · `save_nav_graph` |
| 🐛 **Debugging** | 9 | `debug_attach` · `debug_detach` · `debug_add_breakpoint` · `debug_remove_breakpoint` · `debug_resume` · `debug_backtrace` · `debug_variables` · `debug_run_command` · `debug_task_tree` |
| 📦 **Swift Package** | 7 | `swift_package_resolve` · `swift_package_update` · `swift_package_init` · `swift_package_clean` · `swift_package_show_deps` · `swift_package_dump` · `swift_package_test` |
| 🔎 **Inspection** | 2 | `read_user_defaults` · `write_user_default` |
| ✅ **Quality** | 2 | `lint` · `accessibility_audit` |
| ⚙️ **Extras** | 1 | `open_simulator` |

---

## 🚀 Workflows

### Build & Test

```
discover_projects → list_schemes → session_set_defaults → build_simulator → test_simulator → lint
```

> Discover projects, pick a scheme, build for simulator, run tests, lint for style issues.

### UI Exploration

```
build_run_simulator → screenshot → inspect_ui → tap → type_text → screenshot
```

> Build and launch, screenshot the screen, inspect the accessibility tree, interact with elements, verify the result.

### Debug Session

```
debug_attach → debug_add_breakpoint → debug_resume → debug_backtrace → debug_variables → debug_detach
```

> Attach LLDB, set breakpoints, hit them, inspect the stack and variables, detach cleanly.

### Navigation

```
load_nav_graph → get_nav_graph → where_am_i → navigate_to → where_am_i
```

> Load the app's navigation graph, inspect its structure, identify the current screen, navigate to a target, verify arrival. See [docs/navigation.md](docs/navigation.md) for the full graph schema and authoring guide.

### Physical Device

```
list_devices → session_set_defaults → build_for_device → install_app_device → launch_app_device → device_screenshot
```

> List connected devices, build with code signing, install and launch on hardware, capture a screenshot.

### Swift Package Management

```
swift_package_show_deps → swift_package_resolve → swift_package_update
```

> Inspect the dependency tree, resolve packages, update to latest versions.

---

## 📥 Installation

### Makefile (recommended)

```bash
git clone https://github.com/JAManfredi/ios_mcp.git
cd ios_mcp
make install
```

Installs to `/usr/local/bin` by default. Use `PREFIX=~/.local` to install elsewhere.

### Homebrew (build from source)

```bash
brew install --build-from-source Formula/ios-mcp.rb
```

### Manual

```bash
git clone https://github.com/JAManfredi/ios_mcp.git
cd ios_mcp
brew bundle          # optional dependencies (swiftlint, etc.)
swift build -c release --disable-sandbox
cp .build/release/ios-mcp /usr/local/bin/
```

---

## ⚙️ MCP Client Configuration

Register as an MCP server with your client. For example:

```json
{
  "mcpServers": {
    "ios-mcp": {
      "command": "/usr/local/bin/ios-mcp"
    }
  }
}
```

ios-mcp communicates over **stdio** using the [MCP protocol](https://modelcontextprotocol.io/). It works with any MCP-compatible client — add the binary path to your client's server configuration and restart.

---

### Native UI backend selection (opt-in)

The agent continues calling `inspect_ui` and `tap`. Select their backend when
starting ios-mcp with `--ui-backend auto|native|axe`. The default remains AXe.
The native path has been verified with Xcode 27.1; selection checks actual tool
availability and schemas rather than relying on a version number.

Build/install a binary whose `--help` includes `--ui-backend`, then configure
your MCP client (adjust `command` to your installed binary):

```json
{
  "mcpServers": {
    "ios-mcp": {
      "command": "/usr/local/bin/ios-mcp",
      "args": ["--ui-backend", "auto"]
    }
  }
}
```

After restarting the MCP connection, have the agent set `workspace` or `project`
with `session_set_defaults`. Alternatively, add
`"--native-ui-workspace", "/absolute/path/YourApp.xcodeproj"` to `args` to pin
an existing absolute `.xcodeproj` or `.xcworkspace` path. The pinned path takes
precedence; otherwise the current session's `workspace`, then `project`, is used
for each operation. Clearing defaults removes session-derived context; a pinned
workspace option remains active until the server is restarted without it.

| Mode | Behavior of `inspect_ui` and `tap` |
|------|-----------------------------------|
| `axe` (default) | Use the existing AXe backend without connecting to native Xcode MCP. |
| `native` | Require a project context and native APIs. Missing capabilities and permission failures are errors. |
| `auto` | Prefer native when a project is configured and the required native schemas are available. Select AXe if no project is configured, `mcpbridge` is confirmed missing, or the native catalog is incompatible. |

For backward compatibility, `--native-ui-workspace` alone still selects strict
`native` mode. Combining that option with explicit `axe` mode is a configuration
error. To opt out, remove the workspace option and use `--ui-backend axe` (or
omit both options), then restart the MCP connection.

Boot the intended simulator and launch your app before calling `inspect_ui`.
Supply its exact UUID through `udid` or the `simulator_udid` session default.
When native is selected, Xcode opens the configured project and requests normal
agent/project approval. Keep the Mac unlocked and approve the request in Xcode;
retry inspection if it returned a permission error. An updated executable may
need fresh approval. No permissions are granted automatically.

Automatic selection occurs **before any native workspace, device session, or
input tool call**. Successful native captures and AXe responses in `auto` identify
the selected backend and reason, including when AXe itself fails. Permission
denials, malformed project paths, unknown lookup/connection failures, timeouts,
and native action errors do not
trigger AXe fallback. A tap may have happened before an error was returned:
inspect the screen before deciding whether to repeat it. No tap is automatically
retried through another backend.

Only inspection and taps participate in this selection. Other gestures and
navigation tools retain their existing backends and may still require AXe
(1.8.0+ under Xcode 27). Native inspection returns Apple's text hierarchy and
managed capture paths. Native taps use a fresh hierarchy's hit point or explicit
coordinates in **screen points**, not screenshot pixels. Ambiguous, missing,
disabled, and out-of-bounds targets fail before input.

`ios-mcp doctor` reports toolchain/dependency diagnostics without connecting or
granting access; it does not select a backend or establish authorization.
Automatic selection is experimental and does not imply a performance advantage.
See [validation and limits](docs/native-ui-pilot.md) before enabling it.

## 📋 Requirements

| Dependency | Version | Required |
|-----------|---------|----------|
| macOS | 14+ (26.6+ for Xcode 27) | ✅ |
| Xcode | 16+ (tested through 27.1) | ✅ |
| iOS Simulator runtime | Any installed | ✅ |
| Swift | 6.1+ | ✅ |
| [axe](https://github.com/cameroncooke/AXe) | 1.8.0+ (required for Xcode 27) | Optional — UI automation |
| SwiftLint | Any | Optional — lint tool |
| devicectl (via Xcode) | Xcode 16+ | Optional — physical devices |

### Xcode 27 notes

- Xcode 27 replaced Simulator.app with **Device Hub**. `open_simulator` opens Device Hub and falls back to Simulator.app on older Xcode.
- `device_screenshot` and `record_device_screen` use `devicectl device capture` (Xcode 26.6+).
- `set_orientation`, `reboot_simulator`, and `debug_task_tree` need Xcode 27. `swift_package_test`'s `repeat_until` needs the Swift 6.4 toolchain.
- Device tools read devicectl's JSON v5 `properties` dictionary, with fallback to the fields Xcode 27 deprecated.
- axe below 1.8.0 can't load SimulatorKit under Xcode 27, so `doctor` treats it as a required failure there.
- Xcode 27 also supports headless native MCP. `xcrun mcpbridge` is the stdio connection; `xcrun mcp-server` manages the service and permissions. `lldb-mcp` provides a separate debugger connection. ios-mcp keeps its existing backends by default. An opt-in native UI pilot is available for `inspect_ui` and `tap`; LLDB, other gestures, and navigation tools keep their existing backends.
- `ios-mcp doctor` discovers native binaries in the effective toolchain (including `DEVELOPER_DIR`) and queries service/permission status without connecting, opening a workspace, or granting access. These optional diagnostics do not affect the dependency verdict. Installed binaries and enabled headless mode do not establish agent authorization or backend compatibility. See [native MCP compatibility checks](docs/native-mcp-compatibility.md) for the observed tool schemas, runtime results, and adoption gaps.

---

## 🧠 Session Defaults

`session_set_defaults` stores frequently-used values so they don't need to be repeated on every tool call:

- **simulator_udid** — target simulator
- **device_udid** — target physical device
- **workspace** / **project** — Xcode workspace or project path
- **scheme** — build scheme
- **bundle_id** — app bundle identifier
- **configuration** — Debug / Release

A typical session starts with `discover_projects → list_schemes → session_set_defaults`, after which tools like `build_simulator`, `test_simulator`, and `launch_app` pick up the context automatically. Use `show_session` to inspect current defaults and `clear_session` to reset them.

Some tools auto-set defaults as a side effect:
- `show_build_settings` → `bundle_id`
- `boot_simulator` → `simulator_udid`
- `list_devices` → `device_udid` (when exactly one device is connected)

Session defaults are **validated before use** — if a simulator is deleted or a path no longer exists, the tool returns a `stale_default` error instead of silently using invalid state.

---

## 🔒 Safety

ios-mcp is designed for local development with a security-first posture:

| Feature | Description |
|---------|-------------|
| **No telemetry** | No data leaves your machine |
| **No network access** | Communicates only via stdin/stdout JSON-RPC |
| **Arg-array execution** | All subprocess calls use direct argument arrays — never `/bin/sh -c` |
| **Secret redaction** | Bearer tokens, API keys, signing identities, and provisioning profiles are stripped from output |
| **LLDB denylist** | Dangerous commands (`platform shell`, `memory write`, etc.) blocked by default |
| **Resource locking** | Prevents conflicting operations on the same resource |
| **Session validation** | Stale defaults are caught before use |

---

## 🩺 Doctor

`ios-mcp doctor` checks your environment for required and optional dependencies:

```
$ ios-mcp doctor
ios-mcp doctor
==============

[ok] macOS: 15.3.0
[ok] Xcode: /Applications/Xcode.app/Contents/Developer
[ok] Xcode version: 16.2
[ok] Simulator: simctl available
[ok] LLDB: lldb-1600.0.36.3
[ok] axe: 1.8.0 [ok] checksum verified
[ok] devicectl: available (physical device support)
[--] Device Hub (open_simulator): needs Xcode 27+; falls back to Simulator.app
[--] devicectl capture (device_screenshot, device recording): needs Xcode 26.6+
[--] Simulator orientation (set_orientation): needs Xcode 27+
[--] simctl reboot (reboot_simulator): needs Xcode 27+
[ok] SwiftLint: /usr/local/bin/swiftlint
[ok] ios-mcp version: 0.1.0

Verdict: SUPPORTED — all checks passed.
```

`[!!]` = required (blocks functionality) · `[--]` = optional (some tools unavailable)

---

## 🏗 Architecture

| Module | Role |
|--------|------|
| **Core** | Tool registry, command execution, session state, concurrency policy, artifact store, redaction, validation, log capture, LLDB sessions, video recording, navigation graph store |
| **Tools** | 76 tool implementations across 13 categories |
| **IosMcp** | Executable entry point — MCP server, ArgumentParser routing, `doctor` |

See [AGENTS.md](AGENTS.md) for contributor guidance including coding conventions, error handling patterns, and detailed type documentation.

---

## 📄 License

MIT — see [LICENSE](LICENSE). Third-party dependency licenses in [THIRD_PARTY.md](THIRD_PARTY.md).
