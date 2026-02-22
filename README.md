# ios-mcp

MCP server for headless iOS development via Claude Code. Build, test, debug, and interact with iOS simulators without leaving the terminal.

## Build

```bash
swift build
```

## Run

MCP server mode (stdin/stdout JSON-RPC):
```bash
swift run ios-mcp
```

Environment check:
```bash
swift run ios-mcp doctor
```

## Test

```bash
swift test
```

## Claude Code Configuration

Add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
    "ios-mcp": {
      "command": "/path/to/ios-mcp",
      "args": []
    }
  }
}
```

## Architecture

- **Core** — Shared infrastructure: tool registry, command execution, session state, concurrency control
- **Tools** — Tool implementations organized by category (simulator, build, UI automation, etc.)
- **IosMcp** — Entry point: MCP server setup and `doctor` subcommand

See [AGENTS.md](AGENTS.md) for contributor guidance.
