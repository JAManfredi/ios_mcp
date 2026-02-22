# ios-mcp

## Build & Test

```bash
swift build           # Build all targets
swift test            # Run all tests
swift run ios-mcp doctor  # Environment check
```

## Architecture

See [AGENTS.md](AGENTS.md) for full architecture and coding conventions.

- **Core** — Tool registry, command execution, session state, concurrency, artifacts
- **Tools** — Tool implementations by category (depends on Core)
- **IosMcp** — Entry point (depends on Core + Tools)

## Key Conventions

- Actor-based state management (no classes with locks)
- `CommandExecutor` with arg arrays — never shell execution
- `ToolResponse` for all tool outputs — never throw from handlers
- Swift Testing for tests (`@Test`, `#expect`)
- Strict Swift 6 concurrency
