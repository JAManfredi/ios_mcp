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
| `navigate_to` | Compute the shortest path between two nodes, execute each edge's actions, then check the screen against the target's fingerprint. |
| `where_am_i` | Capture the accessibility tree and match it against node fingerprints. |
| `tag_screen` | Capture a live fingerprint and associate it with a graph node. Protects existing fingerprints by default. |
| `save_nav_graph` | Persist the in-memory graph (including any new fingerprints) to disk. |

### Workflow

```
load_nav_graph → get_nav_graph → where_am_i → navigate_to
```

> Load the graph, inspect its structure, identify where you are, and navigate to a target.

### Arrival check

After running a path, `navigate_to` compares the screen with the target node's fingerprint:

- **Match:** the response ends with `Arrived at '<target>'` and the match confidence. If other nodes match too, it names them.
- **No match:** it checks once more after a short wait (in case the screen was still loading), then returns an error naming what the screen matched instead. Common causes are an edge that leads somewhere else, a missing precondition such as login, or a slow screen.
- **No fingerprint on the target:** the response says `Arrival not checked`. Use `tag_screen` on that screen, or confirm with `screenshot`.

---

## Graph Schema

A navigation graph is a single JSON file with the following top-level structure:

```json
{
  "version": "1.0",
  "app": "my-app",
  "nodes": { ... },
  "edges": [ ... ],
  "commands": [ ... ],
  "references": [ ... ]
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
| `accessibilityLabel` | string | Label the `accessibilityId` element must have. Use it when screens share a component, such as a page title whose ID is the same on every tab but whose text differs. |
| `hierarchyHash` | string | Reserved for future hierarchy-based matching |
| `dominantStaticText` | string | Static text that appears on the screen (medium confidence match). Read from the `AXLabel` of static text and heading elements, so navigation bar titles count. |

A fingerprint with an `accessibilityId` matches only when that ID is on screen and, if the fingerprint has an `accessibilityLabel`, an element with that ID has that label. It is a high-confidence match if its `dominantStaticText` is also on screen (or it has none), and medium if the text is missing. A fingerprint with only `dominantStaticText` matches at medium confidence.

#### SubTab

```json
{
  "id": "trending",
  "name": "Trending",
  "deeplinkTemplate": "myapp://home/trending",
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
| `id` | string | no | Stable edge identifier (e.g. a deeplink case name). Lets `navigate_to` pick this edge with `via`. |
| `from` | string | yes | Source node ID. Use `"*"` for globally routable edges (reachable from any screen). |
| `to` | string | no | Target node ID. Omit for action-only edges (e.g., bet placement). |
| `actions` | [Action] | yes | Ordered list of actions to execute for this transition. |
| `parameters` | [Parameter] | no | Dynamic parameters the edge accepts (for template substitution). |
| `reversible` | bool | no | Whether this edge can be traversed in reverse. |
| `reverseActions` | [Action] | no | Actions to execute for reverse traversal. |
| `preconditions` | [string] | no | Conditions that must be true for traversal (informational). |
| `validated` | bool | no | Whether this edge has been validated at runtime. |
| `navMode` | string | no | How the destination is presented: `push`, `sheet`, `modal`, `tab_switch`, `in_tab`, `action`. Informational. |

Nodes, edges, and the top-level object may carry extra fields (generator metadata such as `generatedAt` or `stateCase`). Tools ignore them, and `save_nav_graph` writes them back unchanged.

#### Choosing among parallel edges

When several edges lead to the same node (for example `search` and `search/{searchTerm}`), `navigate_to` uses the edge whose placeholders are all covered by the supplied `parameters`, preferring the one that uses the most of them. Without parameters it picks an edge that needs none. Pass `via` with an edge `id` or its exact deeplink template to choose one explicitly. `get_nav_graph` with `include_edges=true` (or `node_id`) lists every edge's ID, URL, parameters, and preconditions.
#### Actions

Each action is a single UI operation. Edges can have multiple actions executed in sequence.

| Type | Fields | Description |
|------|--------|-------------|
| `deeplink` | `url` | Open a URL via `simctl openurl` (see [Deep link confirmation prompts](#deep-link-confirmation-prompts)). Supports `{parameter}` template substitution. |
| `tap` | `target` | Tap an element by accessibility ID, label, or coordinates. |
| `swipe` | `direction`, `target` | Swipe in a direction (up/down/left/right), optionally centered on a target. |
| `type_text` | `text`, `target` | Type text with `axe type`. If `target` is set, it is tapped first to focus it. Supports `{parameter}` substitution. |
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

Values may be strings, numbers, or booleans (`true`/`false`). Values substituted into deeplink URLs are percent-encoded (spaces, `/`, `?`, `#`); a value that already contains `%` is treated as pre-encoded and left alone. Invalid `parameters` JSON is rejected.

### Commands

Optional convenience shortcuts for common deeplink-based operations.

```json
{
  "id": "dismiss_modal",
  "description": "Dismiss the topmost modal",
  "deeplinkTemplate": "myapp://nav/dismiss",
  "behavior": "dismiss"
}
```

### References

Optional array of supplemental files that provide lookup data for edge parameters. When `load_nav_graph` runs, it resolves each reference file's path relative to the graph file and surfaces it in the output — so the agent knows exactly where to find parameter values.

```json
{
  "file": "category_ids.json",
  "description": "Category ID lookup table. Maps human-readable names to numeric IDs required by parameterized edges.",
  "usedByNodes": ["category_detail", "item_detail"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | string | yes | Filename relative to the graph file's directory |
| `description` | string | yes | What the file contains and when to use it |
| `usedByNodes` | [string] | no | Node IDs whose edges require values from this file |

The agent workflow with references:
1. `load_nav_graph` → output includes absolute paths to reference files with descriptions
2. Agent reads the reference file to resolve human-readable names to IDs
3. Agent passes resolved IDs as parameters to `navigate_to`

---

## Creating a Navigation Graph

### Option 1: Write by Hand

For simple apps, write the JSON directly. Start with tab roots as nodes and use wildcard (`"*"`) edges for deeplink-based transitions.

### Option 2: Extract from Source Code

For apps with deeplink handlers, write an extraction script that parses route definitions and generates the graph automatically. For example, a Python script that walks Swift deeplink handler source files can produce a complete graph with nodes, edges, and parameter definitions.

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

### Choosing a good fingerprint

A fingerprint only helps if it is unique to its screen. Shared UI such as the tab bar or navigation bar appears on many screens and makes matches ambiguous.

- Pass `accessibility_id` (and optionally `static_text`) to `tag_screen` with values specific to the screen, such as the screen's root view identifier. Both must be present on the current screen.
- Without `accessibility_id`, `tag_screen` picks the first ID on screen that no other node's fingerprint uses and that no other screen tagged in this session showed. Without `static_text`, it picks the first text that passes the same test. Auto-selected values are marked `(auto-selected)`, and the response lists other screen-specific candidates. If every ID is shared, the fingerprint uses text only.
- Tag several screens in one session (for example, each tab root) before relying on auto-selection. The first screen tagged has nothing to compare against, so its choice may be shared UI; the response says so.
- When screens share a component with the same ID, such as a page title, pass that ID as `accessibility_id` and the screen's title as `accessibility_label`. The fingerprint then matches only when the element shows that title, even if the same words appear elsewhere on another screen.
- `tag_screen` warns when another node's fingerprint also matches the current screen. Re-tag that node on its own screen with `force=true` and an element this screen doesn't have.
- When several nodes match equally well, `where_am_i` reports them all as ambiguous instead of guessing, and `navigate_to` asks for an explicit `from`.

Which elements each tagged screen showed is kept in memory only, for the session. Loading a graph clears it.

`save_nav_graph` writes the original file contents with fingerprint changes applied, so fields the tools don't model are preserved. To leave the source graph untouched, pass a separate `path` argument.

---

## JSON Schema

A formal JSON Schema for validation is available at [`Sources/Core/nav_graph_schema.json`](../Sources/Core/nav_graph_schema.json).

## Deep link confirmation prompts

The first time `simctl openurl` opens a custom scheme on a simulator, iOS can ask "Open in “App”?" and wait. AXe can't tap that system alert, and each later link queues another prompt behind it. Simulators that have already approved the scheme don't ask, so this shows up on new simulators, such as ones created on a CI host.

To avoid it, `deep_link` and `navigate_to` do this the first time a session opens a custom scheme on a simulator:

1. Find the user-installed app whose `Info.plist` declares the scheme. If exactly one does, record the approval iOS would store when someone taps Open: `simctl spawn <udid> defaults write com.apple.launchservices.schemeapproval "com.apple.CoreSimulator.CoreSimulatorBridge--><scheme>" -string <bundle id>`.
2. Open the URL.
3. Check the screen once for the prompt. If it appears, return an error instead of reporting that the link opened. If not, later links with that scheme skip steps 1 and 3.

`http` and `https` links skip all of this. Prompt detection matches the English alert text. If several apps declare the scheme, no approval is recorded and the response says so.
