# Navigation Graph

ios-mcp includes 6 navigation tools that enable structured, graph-based navigation through iOS apps. These tools are **optional** — all UI automation works without them — but when a navigation graph is provided, they enable deterministic pathfinding and screen identification.

---

## Overview

A navigation graph is a JSON file that describes an app's screens (nodes), the transitions between them (edges), and the actions needed to traverse each transition. Once loaded, the MCP can:

- **Navigate between screens** via BFS shortest-path computation
- **Identify the current screen** by matching accessibility fingerprints
- **Execute multi-step transitions** combining deeplinks, taps, swipes, text input, and key presses

Without a graph, all navigation tools gracefully fall back to guidance pointing at `inspect_ui`, `tap`, `swipe`, and `deep_link` for manual navigation.

---

## Tools

| Tool | Description |
|------|-------------|
| `load_nav_graph` | Load a graph from a JSON file. Auto-searches common locations if no path is given. |
| `get_nav_graph` | View the loaded graph's nodes, edges, and commands. Supports filtering by node ID. |
| `navigate_to` | Compute the shortest path between two nodes and execute each edge's actions. |
| `where_am_i` | Capture the accessibility tree and match it against node fingerprints. |
| `tag_screen` | Capture a live fingerprint and associate it with a graph node. Protects existing fingerprints by default. |
| `save_nav_graph` | Persist the in-memory graph (including any new fingerprints) to disk. |

### Workflow

```
load_nav_graph → get_nav_graph → where_am_i → navigate_to → where_am_i
```

> Load the graph, inspect its structure, identify where you are, navigate to a target, verify arrival.

---

## Graph Schema

A navigation graph is a single JSON file with the following top-level structure:

```json
{
  "version": "1.0",
  "app": "my-app",
  "nodes": { ... },
  "edges": [ ... ],
  "commands": [ ... ]
}
```

### Nodes

Each node represents a screen or distinct UI state in the app.

```json
{
  "home": {
    "id": "home",
    "name": "Home",
    "isTabRoot": true,
    "deeplinkTemplate": "myapp://home",
    "fingerprint": {
      "accessibilityId": "HomeScreenRoot",
      "dominantStaticText": "Welcome"
    }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique identifier, matches the key in the `nodes` object |
| `name` | string | yes | Human-readable screen name |
| `isTabRoot` | bool | yes | Whether this node is a root tab destination |
| `deeplinkTemplate` | string | no | URL template for direct navigation (informational) |
| `supportedTabs` | [string] | no | Tab identifiers this node appears under |
| `isCMSDriven` | bool | no | Whether the screen's content is CMS-managed |
| `subTabs` | [SubTab] | no | Sub-tab destinations within this screen |
| `fingerprint` | Fingerprint | no | Accessibility fingerprint for screen identification |
| `validated` | bool | no | Whether this node has been validated at runtime |

#### Fingerprint

Fingerprints enable `where_am_i` and auto-detection in `navigate_to`.

| Field | Type | Description |
|-------|------|-------------|
| `accessibilityId` | string | A unique accessibility identifier present on this screen (high confidence match) |
| `hierarchyHash` | string | Reserved for future hierarchy-based matching |
| `dominantStaticText` | string | The most prominent static text on the screen (medium confidence match) |

Matching priority: `accessibilityId` (high confidence) > `dominantStaticText` (medium confidence).

#### SubTab

```json
{
  "id": "nfl",
  "name": "NFL",
  "deeplinkTemplate": "myapp://sports/nfl",
  "parameters": [...]
}
```

### Edges

Each edge defines a transition between two nodes and the actions needed to traverse it.

```json
{
  "from": "home",
  "to": "search",
  "actions": [
    { "type": "tap", "target": { "accessibilityId": "SearchButton" } }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `from` | string | yes | Source node ID. Use `"*"` for globally routable edges (reachable from any screen). |
| `to` | string | no | Target node ID. Omit for action-only edges (e.g., bet placement). |
| `actions` | [Action] | yes | Ordered list of actions to execute for this transition. |
| `parameters` | [Parameter] | no | Dynamic parameters the edge accepts (for template substitution). |
| `reversible` | bool | no | Whether this edge can be traversed in reverse. |
| `reverseActions` | [Action] | no | Actions to execute for reverse traversal. |
| `preconditions` | [string] | no | Conditions that must be true for traversal (informational). |
| `validated` | bool | no | Whether this edge has been validated at runtime. |

#### Actions

Each action is a single UI operation. Edges can have multiple actions executed in sequence.

| Type | Fields | Description |
|------|--------|-------------|
| `deeplink` | `url` | Open a URL via `simctl openurl`. Supports `{parameter}` template substitution. |
| `tap` | `target` | Tap an element by accessibility ID, label, or coordinates. |
| `swipe` | `direction`, `target` | Swipe in a direction (up/down/left/right), optionally centered on a target. |
| `type_text` | `text`, `target` | Type text into the focused field or a target element. Supports `{parameter}` substitution. |
| `key_press` | `key` | Send a key press (return, escape, backspace, tab, etc.). |

**Action target fields** (for `tap`, `swipe`, `type_text`):

| Field | Type | Description |
|-------|------|-------------|
| `accessibilityId` | string | Accessibility identifier (preferred) |
| `accessibilityLabel` | string | Accessibility label |
| `x` | number | X coordinate |
| `y` | number | Y coordinate |

#### Parameters

```json
{
  "name": "event_id",
  "type": "string",
  "required": true,
  "exampleValue": "12345"
}
```

Template parameters in deeplink URLs and text fields use `{name}` syntax. Pass values via the `parameters` argument on `navigate_to`:

```
navigate_to(target: "event_detail", parameters: '{"event_id": "12345"}')
```

### Commands

Optional convenience shortcuts for common deeplink-based operations.

```json
{
  "id": "open_bet_slip",
  "description": "Open the bet slip overlay",
  "deeplinkTemplate": "myapp://betslip",
  "behavior": "overlay"
}
```

---

## Creating a Navigation Graph

### Option 1: Write by Hand

For simple apps, write the JSON directly. Start with tab roots as nodes and use wildcard (`"*"`) edges for deeplink-based transitions.

### Option 2: Extract from Source Code

For apps with deeplink handlers, write an extraction script that parses route definitions and generates the graph. The [DraftKings extraction script](https://github.com/JAManfredi/gaming-native-ios/blob/develop/nav-graph/extract_nav_graph.py) is an example of this approach — it parses Swift deeplink handler source files and generates a graph with 18 nodes and 44 edges.

### Option 3: Crawl at Runtime

Use `inspect_ui` + `tap`/`swipe` to explore the app manually, then use `tag_screen` to record fingerprints as you go. Build up the graph incrementally. This is slower but works for any app without source access.

### Recommendations

- Start with **nodes for every major screen** (tabs, modals, detail views)
- Use **wildcard edges** (`from: "*"`) for screens reachable via deeplink from anywhere
- Use **specific edges** (`from: "home"`) for tap/swipe transitions that only work from certain screens
- Add **fingerprints** to nodes you want `where_am_i` and auto-detection to recognize
- Keep the graph in your project's `nav-graph/` directory (or any stable location)

---

## Graceful Degradation

All 6 navigation tools work without a loaded graph:

| Tool | Behavior without graph |
|------|----------------------|
| `load_nav_graph` | Reports no graph found, suggests `inspect_ui` |
| `get_nav_graph` | Reports no graph loaded, suggests `inspect_ui` and `load_nav_graph` |
| `navigate_to` | Reports no graph loaded, suggests `inspect_ui` and `load_nav_graph` |
| `where_am_i` | Reports no graph loaded, suggests `inspect_ui` |
| `tag_screen` | Returns error (requires a graph to tag against) |
| `save_nav_graph` | Returns error (nothing to save) |

The first four return **success responses with guidance**, not errors, so MCP clients can continue without interruption.

---

## Fingerprint Protection

`tag_screen` defaults to **not overwriting** existing fingerprints. This protects carefully authored fingerprints in predefined graphs from being accidentally replaced by runtime captures (which may be less reliable on screens with weak accessibility identifiers).

Use `force=true` only when you intentionally want to replace a fingerprint.

`save_nav_graph` writes the full in-memory graph. To avoid overwriting the source graph, pass a separate `path` argument.

---

## JSON Schema

A formal JSON Schema for validation is available at [`Sources/Core/nav_graph_schema.json`](../Sources/Core/nav_graph_schema.json).
