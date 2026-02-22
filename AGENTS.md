# ios-mcp — Agent Guidance

## Project Purpose

ios-mcp is a Model Context Protocol (MCP) server that gives Claude Code full control over the iOS development lifecycle: project discovery, simulator management, building, testing, UI automation, debugging, and quality checks — all headless, all from the CLI.

## Architecture

### Module Layout

| Module | Role |
|--------|------|
| **Core** | Shared infrastructure — tool registry, command execution, session state, concurrency policy, artifact store |
| **Tools** | Tool implementations grouped by category. Each subdirectory maps to a tool category. |
| **IosMcp** | Executable entry point — MCP server startup, ArgumentParser routing |

### How Tools Work

1. Each tool has a `ToolManifest` describing its name, input schema, category, and flags.
2. Tools register a handler closure with the `ToolRegistry` actor.
3. The MCP server delegates `tools/list` and `tools/call` to the registry.
4. Handlers receive `[String: Value]` arguments and return a `ToolResponse`.

### Key Types

- `ToolManifest` — Metadata describing a tool's interface
- `ToolRegistry` — Actor that maps tool names to handlers
- `ToolResponse` — Success (content + optional artifacts) or typed error
- `CommandExecutor` — Async `Process` wrapper (arg arrays only, no shell)
- `SessionStore` — Actor holding session-scoped defaults (simulator UDID, workspace, scheme, etc.)
- `ConcurrencyPolicy` — Actor preventing conflicting operations on the same resource
- `ArtifactStore` — File-backed storage for screenshots, logs, and transient outputs

## Coding Conventions

### Swift Concurrency
- All shared mutable state lives in **actors** (`SessionStore`, `ToolRegistry`, `ConcurrencyPolicy`, `ArtifactStore`).
- Tool handlers are `@Sendable` async closures.
- Target Swift 6 strict concurrency.

### Command Execution
- **Always use `CommandExecutor` with argument arrays.** Never use shell execution (`/bin/sh -c`).
- Pass executables as full paths (e.g., `/usr/bin/xcrun`) or use `xcrun` to locate tools.

### Error Handling
- Return `ToolResponse.error` with a typed `ErrorCode` — don't throw from tool handlers.
- Use specific error codes: `resource_busy`, `dependency_missing`, `command_failed`, etc.

### Structured Responses
- Tool output should be structured text that Claude can parse.
- Include artifact references for binary outputs (screenshots, logs).

### Testing
- Use Swift Testing framework (`@Test`, `#expect`).
- Core infrastructure tests in `CoreTests`.
- Tool-level tests in `ToolTests`.
- Prefer testing through public interfaces over internal implementation details.

## Tool Categories

| Category | Directory | Examples |
|----------|-----------|----------|
| Project Discovery | `Tools/ProjectDiscovery/` | discover_projects, list_schemes, show_build_settings |
| Simulator | `Tools/Simulator/` | list_simulators, boot, shutdown, erase |
| Build | `Tools/Build/` | build_sim, build_run_sim, test, clean |
| Logging | `Tools/Logging/` | start_log_capture, stop_log_capture |
| UI Automation | `Tools/UIAutomation/` | screenshot, snapshot_ui, tap, swipe |
| Debugging | `Tools/Debugging/` | LLDB tools |
| Inspection | `Tools/Inspection/` | read_user_defaults |
| Quality | `Tools/Quality/` | lint, accessibility_audit |
| Extras | `Tools/Extras/` | open_simulator |

## Phase 1 Scope

Phase 1 focuses on project discovery, simulator management, and basic build/test tools. UI automation, debugging, and quality tools come in later phases.
