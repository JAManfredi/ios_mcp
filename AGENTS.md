# ios-mcp — Agent Guidance

## Project Purpose

ios-mcp is a Model Context Protocol (MCP) server that gives Claude Code full control over the iOS development lifecycle: project discovery, simulator management, building, testing, UI automation, debugging, and quality checks — all headless, all from the CLI.

## Architecture

### Module Layout

| Module | Role |
|--------|------|
| **Core** | Shared infrastructure — tool registry, command execution, session state, concurrency policy, artifact store, redaction, validation, next-step resolution, log capture management, LLDB session management |
| **Tools** | 37 tool implementations grouped into 9 categories. Each subdirectory maps to a tool category. |
| **IosMcp** | Executable entry point — MCP server startup, ArgumentParser routing, `doctor` diagnostic command |

### How Tools Work

1. Each tool has a `ToolManifest` describing its name, input schema, category, and `isDestructive` flag.
2. Tools register a handler closure with the `ToolRegistry` actor via `ToolRegistration.registerAll()`.
3. The MCP server delegates `tools/list` and `tools/call` to the registry.
4. Handlers receive `[String: Value]` arguments and return a `ToolResponse` (`.success` or `.error`).
5. Successful responses include `nextSteps` — suggested follow-up tools resolved by `NextStepResolver`.

### Core Infrastructure Types

| Type | Role |
|------|------|
| `ToolManifest` | Metadata describing a tool's name, input schema, category, and destructive flag |
| `ToolRegistry` | Actor mapping tool names to handler closures |
| `ToolResponse` | `.success(ToolResult)` or `.error(ToolError)` — every handler returns this, never throws |
| `ToolResult` | Content string + optional artifact references + next steps |
| `ToolError` | Typed error with `ErrorCode`, message, and optional details |
| `CommandExecutor` | Async `Process` wrapper — arg arrays only, no shell execution. Applies `Redactor` automatically. Supports cancellation. |
| `SessionStore` | Actor holding session-scoped defaults (simulator UDID, workspace, scheme, bundle ID, configuration, derived data path) |
| `ConcurrencyPolicy` | Actor-based resource locking — prevents conflicting operations on the same resource |
| `ArtifactStore` | File-backed storage for screenshots, logs, and transient outputs. TTL-based eviction + size cap. Periodic stale directory cleanup. |
| `DefaultsValidator` | Validates session defaults (UDIDs, paths) against actual system state. Returns `stale_default` errors. |
| `Redactor` | Pattern-based secret redaction (Bearer tokens, API keys, signing identities, provisioning profiles). Applied automatically by `CommandExecutor`. |
| `NextStepResolver` | Static mapping from tool names to suggested follow-up tools. Every tool has a next-step chain. |
| `LLDBSessionManager` | Actor managing persistent LLDB subprocesses for interactive debugging. Audit-logs all commands. |
| `LogCaptureManager` | Actor managing background `simctl spawn <udid> log stream` processes with ring-buffer retention. |
| `RingBuffer` | Fixed-capacity circular buffer used by log capture to bound memory usage. |

### Error Handling

Every tool handler returns `ToolResponse` — never throws. Errors use typed `ErrorCode` values:

| Code | Meaning |
|------|---------|
| `resource_busy` | Another operation holds the lock for this resource (e.g., concurrent builds) |
| `dependency_missing` | Required external tool not found (e.g., `swiftlint`, `axe`) |
| `stale_default` | Session default (UDID, path) no longer valid — device deleted or path moved |
| `command_denied` | LLDB command blocked by denylist |
| `command_failed` | Subprocess exited non-zero |
| `timeout` | Operation exceeded its time limit |
| `invalid_input` | Missing required parameter or invalid argument value |
| `internal_error` | Unexpected failure |

### Validation Patterns

`DefaultsValidator` checks session defaults before use:
- **UDID validation**: Queries `simctl list devices -j` to confirm the simulator exists. Returns `stale_default` if the UDID is gone.
- **Path validation**: Checks filesystem existence. Returns `stale_default` if the path is missing.
- **Graceful degradation**: If `simctl` itself fails, validation passes (avoids false negatives).

Tools that accept fallback from `SessionStore` validate before using stale defaults.

### Secret Redaction

`Redactor` removes secrets from command output before it reaches the MCP client:
- Bearer tokens → `Bearer [REDACTED]`
- API keys / secrets / tokens / passwords → `key: [REDACTED]`
- Signing identities → `Signing Identity: "[REDACTED]"`
- Provisioning profiles → `Provisioning Profile: "[REDACTED]"`

Redaction is applied automatically by `CommandExecutor` to both stdout and stderr.

### NextSteps in Tool Responses

Every successful `ToolResult` includes a `nextSteps` array of `NextStep(tool:description:)`. These are resolved by `NextStepResolver` based on natural workflow progression:
- `discover_projects` → `list_schemes`, `session_set_defaults`
- `build_sim` → `build_run_sim`, `test_sim`, `launch_app`
- `build_run_sim` → `screenshot`, `snapshot_ui`, `start_log_capture`, `debug_attach`
- `debug_attach` → `debug_breakpoint_add`, `debug_stack`, `debug_variables`

All 37 tools have next-step mappings.

### LLDB Denylist

`debug_lldb_command` checks commands against a denylist before execution. Denied commands and their safe alternatives:

| Command Pattern | Reason | Alternative |
|----------------|--------|-------------|
| `platform shell` | Arbitrary shell execution | Use MCP tools |
| `command script` | Arbitrary Python scripts | Not available |
| `command source` | Source arbitrary files | Not available |
| `process kill` | Kill target process | Use `stop_app` |
| `process destroy` | Destroy target process | Use `stop_app` |
| `memory write` | Memory mutation | Read-only inspection |
| `register write` | Register mutation | Read-only inspection |
| `expression @import` | Load frameworks | `expression` without `@import` |
| `settings set target.run-args` | Modify launch args | Use `build_run_sim` |
| `target delete` | Remove debug target | Use `debug_detach` |

Set `allow_unsafe: true` to bypass — response is marked `[UNSAFE]` and audit-logged. **Never set `allow_unsafe: true` without explicit user confirmation.** The denylist exists to prevent accidental damage.

### Concurrency / Resource Locking

`ConcurrencyPolicy` prevents conflicting operations:
- **Simulator operations**: Locked per `simulator:{udid}` — one boot/shutdown/erase at a time per device
- **Build operations**: Locked per build key — one active build/test per workspace
- **Debug sessions**: Locked per `lldb:{pid}` — one LLDB session per process
- **Log capture**: Lock acquired and released immediately after starting capture

If a resource is busy, the tool returns `resource_busy` with the lock owner.

## Coding Conventions

### Swift Concurrency
- All shared mutable state lives in **actors** (`SessionStore`, `ToolRegistry`, `ConcurrencyPolicy`, `ArtifactStore`, `LLDBSessionManager`, `LogCaptureManager`).
- Tool handlers are `@Sendable` async closures.
- Target Swift 6 strict concurrency — no data races.

### Command Execution
- **Always use `CommandExecutor` with argument arrays.** Never use shell execution (`/bin/sh -c`).
- Pass executables as full paths (e.g., `/usr/bin/xcrun`) or use `xcrun` to locate tools.
- Cancellation: `CommandExecutor` terminates child processes on Task cancellation.

### Error Handling
- Return `ToolResponse.error` with a typed `ErrorCode` — don't throw from tool handlers.
- Validate session defaults with `DefaultsValidator` before use.
- Check `ConcurrencyPolicy` locks before long-running operations.

### Structured Responses
- Tool output is structured text that Claude can parse.
- Include artifact references for binary outputs (screenshots).
- Include `nextSteps` for workflow progression guidance.

### Testing
- Use Swift Testing framework (`@Test`, `#expect`, `@Suite`).
- Core infrastructure tests in `CoreTests`.
- Tool-level tests in `ToolTests` using mock `CommandExecuting` and mock session managers.
- Integration tests in `IntegrationTests` gated with `CI_INTEGRATION` environment variable.
- Prefer testing through public interfaces over internal implementation details.

## Tool Categories (37 tools)

| Category | Directory | Count | Tools |
|----------|-----------|-------|-------|
| Project Discovery | `Tools/ProjectDiscovery/` | 3 | `discover_projects`, `list_schemes`, `show_build_settings` |
| Simulator | `Tools/Simulator/` | 5 | `list_simulators`, `boot_simulator`, `shutdown_simulator`, `erase_simulator`, `session_set_defaults` |
| Build | `Tools/Build/` | 6 | `build_sim`, `build_run_sim`, `test_sim`, `launch_app`, `stop_app`, `clean_derived_data` |
| Logging | `Tools/Logging/` | 2 | `start_log_capture`, `stop_log_capture` |
| UI Automation | `Tools/UIAutomation/` | 8 | `screenshot`, `snapshot_ui`, `deep_link`, `tap`, `swipe`, `type_text`, `key_press`, `long_press` |
| Debugging | `Tools/Debugging/` | 8 | `debug_attach`, `debug_detach`, `debug_breakpoint_add`, `debug_breakpoint_remove`, `debug_continue`, `debug_stack`, `debug_variables`, `debug_lldb_command` |
| Inspection | `Tools/Inspection/` | 2 | `read_user_defaults`, `write_user_default` |
| Quality | `Tools/Quality/` | 2 | `lint`, `accessibility_audit` |
| Extras | `Tools/Extras/` | 1 | `open_simulator` |

## Workflow Examples

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

1. Attach LLDB to the running app (returns session ID)
2. Add a breakpoint by symbol or file:line
3. Continue execution until the breakpoint is hit
4. Inspect the call stack
5. Examine frame variables
6. Detach the debugger and clean up

### Log Investigation

```
start_log_capture → [interact with app] → stop_log_capture
```

1. Start capturing logs with optional subsystem/category/process filters
2. Perform app interactions (tap, type, navigate)
3. Stop capture and retrieve filtered log entries with timestamps
