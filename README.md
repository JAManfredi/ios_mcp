<p align="center">
  <pre align="center">
  ┌─────────────────────────────────────────────┐
  │                                             │
  │   ╦╔═╗╔═╗   ╔╦╗╔═╗╔═╗                     │
  │   ║║ ║╚═╗───║║║║  ╠═╝                      │
  │   ╩╚═╝╚═╝   ╩ ╩╚═╝╩                        │
  │                                             │
  │   headless iOS dev, straight from the CLI   │
  │                                             │
  └─────────────────────────────────────────────┘
  </pre>
</p>

<p align="center">
  <a href="https://modelcontextprotocol.io/"><img src="https://img.shields.io/badge/MCP-Compatible-blue?style=flat-square" alt="MCP Compatible"></a>
  <a href="https://github.com/apple/swift"><img src="https://img.shields.io/badge/Swift-6.1+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.1+"></a>
  <a href="https://developer.apple.com/xcode/"><img src="https://img.shields.io/badge/Xcode-16+-147EFB?style=flat-square&logo=xcode&logoColor=white" alt="Xcode 16+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  An <a href="https://modelcontextprotocol.io/">MCP</a> server that gives Claude Code full control over the iOS development lifecycle — <b>55 tools</b> for project discovery, simulator &amp; device management, building, testing, UI automation, debugging, package management, and quality checks.
</p>

---

## ⚡ Quick Start

```bash
# Install
git clone https://github.com/JAManfredi/ios_mcp.git && cd ios_mcp
make install

# Register with Claude Code
claude mcp add -s user ios-mcp /usr/local/bin/ios-mcp

# Verify
ios-mcp doctor
```

---

## 🛠 What's Included

**55 tools** across **12 categories**:

| Category | Count | Tools |
|----------|:-----:|-------|
| 🔍 **Project Discovery** | 3 | `discover_projects` · `list_schemes` · `show_build_settings` |
| 📱 **Simulator** | 5 | `list_simulators` · `boot_simulator` · `shutdown_simulator` · `erase_simulator` · `session_set_defaults` |
| 🔨 **Build** | 8 | `build_sim` · `build_run_sim` · `test_sim` · `launch_app` · `stop_app` · `clean_derived_data` · `inspect_xcresult` · `list_crash_logs` |
| 📲 **Device** | 8 | `list_devices` · `build_device` · `build_run_device` · `test_device` · `install_app_device` · `launch_app_device` · `stop_app_device` · `device_screenshot` |
| 📋 **Logging** | 2 | `start_log_capture` · `stop_log_capture` |
| 👆 **UI Automation** | 10 | `screenshot` · `snapshot_ui` · `deep_link` · `tap` · `swipe` · `type_text` · `key_press` · `long_press` · `start_recording` · `stop_recording` |
| 🐛 **Debugging** | 8 | `debug_attach` · `debug_detach` · `debug_breakpoint_add` · `debug_breakpoint_remove` · `debug_continue` · `debug_stack` · `debug_variables` · `debug_lldb_command` |
| 📦 **Swift Package** | 6 | `swift_package_resolve` · `swift_package_update` · `swift_package_init` · `swift_package_clean` · `swift_package_show_deps` · `swift_package_dump` |
| 🔎 **Inspection** | 2 | `read_user_defaults` · `write_user_default` |
| ✅ **Quality** | 2 | `lint` · `accessibility_audit` |
| ⚙️ **Extras** | 1 | `open_simulator` |

---

## 🚀 Workflows

### Build & Test

```
discover_projects → list_schemes → session_set_defaults → build_sim → test_sim → lint
```

> Discover projects, pick a scheme, build for simulator, run tests, lint for style issues.

### UI Exploration

```
build_run_sim → screenshot → snapshot_ui → tap → type_text → screenshot
```

> Build and launch, screenshot the screen, inspect the accessibility tree, interact with elements, verify the result.

### Debug Session

```
debug_attach → debug_breakpoint_add → debug_continue → debug_stack → debug_variables → debug_detach
```

> Attach LLDB, set breakpoints, hit them, inspect the stack and variables, detach cleanly.

### Physical Device

```
list_devices → session_set_defaults → build_device → install_app_device → launch_app_device → device_screenshot
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

## ⚙️ Claude Code Configuration

Register as an MCP server:

```bash
claude mcp add -s user ios-mcp /usr/local/bin/ios-mcp
```

This adds ios-mcp as a user-scoped MCP server available in all projects. Restart Claude Code to connect.

---

## 📋 Requirements

| Dependency | Version | Required |
|-----------|---------|----------|
| macOS | 14+ | ✅ |
| Xcode | 16+ | ✅ |
| iOS Simulator runtime | Any installed | ✅ |
| Swift | 6.1+ | ✅ |
| [axe](https://github.com/cameroncooke/AXe) | 0.4.0+ | Optional — UI automation |
| SwiftLint | Any | Optional — lint tool |
| devicectl (via Xcode) | Xcode 16+ | Optional — physical devices |

---

## 🧠 Session Defaults

`session_set_defaults` stores frequently-used values so they don't need to be repeated on every tool call:

- **simulator_udid** — target simulator
- **device_udid** — target physical device
- **workspace** / **project** — Xcode workspace or project path
- **scheme** — build scheme
- **bundle_id** — app bundle identifier
- **configuration** — Debug / Release

A typical session starts with `discover_projects → list_schemes → session_set_defaults`, after which tools like `build_sim`, `test_sim`, and `launch_app` pick up the context automatically.

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
[ok] axe: 0.4.0 [ok] checksum verified
[ok] devicectl: available (physical device support)
[ok] SwiftLint: /usr/local/bin/swiftlint
[ok] ios-mcp version: 0.1.0

Verdict: SUPPORTED — all checks passed.
```

`[!!]` = required (blocks functionality) · `[--]` = optional (some tools unavailable)

---

## 🏗 Architecture

| Module | Role |
|--------|------|
| **Core** | Tool registry, command execution, session state, concurrency policy, artifact store, redaction, validation, log capture, LLDB sessions, video recording |
| **Tools** | 55 tool implementations across 12 categories |
| **IosMcp** | Executable entry point — MCP server, ArgumentParser routing, `doctor` |

See [AGENTS.md](AGENTS.md) for contributor guidance including coding conventions, error handling patterns, and detailed type documentation.

---

## 📄 License

MIT — see [LICENSE](LICENSE). Third-party dependency licenses in [THIRD_PARTY.md](THIRD_PARTY.md).
