# ios-mcp

An [MCP](https://modelcontextprotocol.io/) server that gives Claude Code full control over the iOS development lifecycle — project discovery, simulator management, building, testing, UI automation, debugging, and quality checks — all headless, all from the CLI.

## Requirements

| Dependency | Version | Required |
|-----------|---------|----------|
| macOS | 14+ | Yes |
| Xcode | 16+ | Yes |
| iOS Simulator runtime | Any installed | Yes |
| Swift | 6.1+ | Yes |
| [axe](https://github.com/nicklama/axe) | 0.4.0+ | No — UI automation tools only |
| SwiftLint | Any | No — lint tool only |

## Installation

Build from source:

```bash
git clone <repo-url>
cd ios-mcp
swift build -c release
```

Install the binary:

```bash
cp .build/release/ios-mcp /usr/local/bin/
```

Verify your environment:

```bash
ios-mcp doctor
```

## Claude Code Configuration

Add to your MCP settings (`~/.claude/settings.json` or project-level `.claude/settings.json`):

```json
{
  "mcpServers": {
    "ios-mcp": {
      "command": "/usr/local/bin/ios-mcp",
      "args": []
    }
  }
}
```

## What's Included

37 tools across 9 categories:

| Category | Tools |
|----------|-------|
| **Project Discovery** | `discover_projects`, `list_schemes`, `show_build_settings` |
| **Simulator** | `list_simulators`, `boot_simulator`, `shutdown_simulator`, `erase_simulator`, `session_set_defaults` |
| **Build** | `build_sim`, `build_run_sim`, `test_sim`, `launch_app`, `stop_app`, `clean_derived_data` |
| **Logging** | `start_log_capture`, `stop_log_capture` |
| **UI Automation** | `screenshot`, `snapshot_ui`, `deep_link`, `tap`, `swipe`, `type_text`, `key_press`, `long_press` |
| **Debugging** | `debug_attach`, `debug_detach`, `debug_breakpoint_add`, `debug_breakpoint_remove`, `debug_continue`, `debug_stack`, `debug_variables`, `debug_lldb_command` |
| **Inspection** | `read_user_defaults`, `write_user_default` |
| **Quality** | `lint`, `accessibility_audit` |
| **Extras** | `open_simulator` |

## Quick Start Workflows

### Build & Test

```
discover_projects → list_schemes → session_set_defaults → build_sim → test_sim → lint
```

1. Discover workspaces/projects in a directory
2. List available schemes
3. Set simulator, workspace, and scheme as session defaults
4. Build for simulator (returns error/warning counts + xcresult path)
5. Run tests (returns pass/fail/skip counts + failing test names)
6. Lint the project for style issues

### UI Exploration

```
build_run_sim → screenshot → snapshot_ui → tap → type_text → screenshot
```

1. Build, install, and launch the app on simulator
2. Take a screenshot to see the current state
3. Capture the accessibility tree to identify elements
4. Tap a text field by accessibility identifier
5. Type text into the focused field
6. Take another screenshot to verify the result

### Debug Session

```
debug_attach → debug_breakpoint_add → debug_continue → debug_stack → debug_variables → debug_detach
```

1. Attach LLDB to the running app
2. Add a breakpoint by symbol or file:line
3. Continue execution until the breakpoint is hit
4. Inspect the call stack
5. Examine frame variables
6. Detach the debugger and clean up

## Session Defaults

`session_set_defaults` stores frequently-used values (simulator UDID, workspace path, scheme, bundle ID, configuration) so they don't need to be repeated on every tool call. All tools fall back to session defaults when explicit arguments are omitted.

A typical session starts with:

```
discover_projects → list_schemes → session_set_defaults
```

After that, tools like `build_sim`, `test_sim`, and `launch_app` pick up the workspace, scheme, and simulator automatically.

Some tools auto-set defaults as a side effect:
- `show_build_settings` sets `bundle_id` from `PRODUCT_BUNDLE_IDENTIFIER`
- `boot_simulator` sets `simulator_udid`

Session defaults are validated before use — if a simulator is deleted or a path no longer exists, the tool returns a `stale_default` error instead of silently using invalid state.

## Safety

ios-mcp is designed for local development with a security-first posture:

- **No telemetry** — no data leaves your machine
- **No network access** — the server communicates only via stdin/stdout JSON-RPC
- **Argument-array execution** — all subprocess calls use direct argument arrays, never shell execution (`/bin/sh -c`)
- **Secret redaction** — Bearer tokens, API keys, signing identities, and provisioning profiles are automatically stripped from command output before reaching the MCP client
- **LLDB denylist** — dangerous commands (`platform shell`, `process kill`, `memory write`, etc.) are blocked by default. The `allow_unsafe` flag exists for intentional use but requires explicit confirmation and is audit-logged
- **Resource locking** — `ConcurrencyPolicy` prevents conflicting operations (parallel builds on the same workspace, simultaneous simulator boots on the same device)
- **Session validation** — stale defaults (deleted simulators, moved paths) are caught before use

## Doctor

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
[ok] SwiftLint: /usr/local/bin/swiftlint
[ok] ios-mcp version: 0.1.0

Verdict: SUPPORTED — all checks passed.
```

Items marked `[!!]` are required and will prevent ios-mcp from functioning. Items marked `[--]` are optional — the server works without them but specific tools will be unavailable.

## Architecture

| Module | Role |
|--------|------|
| **Core** | Shared infrastructure — tool registry, command execution, session state, concurrency policy, artifact store, redaction, validation, log capture, LLDB session management |
| **Tools** | 37 tool implementations grouped into 9 categories |
| **IosMcp** | Executable entry point — MCP server startup, ArgumentParser routing, `doctor` subcommand |

See [AGENTS.md](AGENTS.md) for contributor guidance including coding conventions, error handling patterns, and detailed type documentation.

## Third-Party Dependencies

See [THIRD_PARTY.md](THIRD_PARTY.md) for license information.

## License

See [LICENSE](LICENSE) for details.
