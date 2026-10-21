# Native UI pilot

Author: Jared Manfredi

The `--native-ui-workspace /absolute/path/App.xcodeproj` option routes only
`inspect_ui` and `tap` through Xcode's native MCP tools. `.xcworkspace` is also
supported. Without this option, every tool uses its existing backend.

## Behavior and ownership

Each operation connects an owned `xcrun mcpbridge`, checks the required tool
schemas, opens the configured project to request normal Xcode authorization,
and starts one device interaction session. It verifies the returned simulator
UUID exactly before capturing or sending input. Xcode may prompt again when the
agent executable changes. Keep the Mac unlocked for approval. The project is
left open because it may already belong to another client; ios-mcp does not
close shared workspaces, stop the shared native service, or change permissions.

For `tap`, a fresh hierarchy resolves identifiers/labels to Apple's `hitPoint`.
Coordinates use screen points. Duplicate targets, incomplete/malformed
hierarchies, disabled targets, missing hit points, and targets requiring another
app to be activated are rejected. Explicit coordinates must lie inside a window.
The app can still change between capture and input; this pilot does not provide
an atomic element action or promise that a completed tap had the intended effect.
Use the returned post-action capture to check the result.

Native filenames include the private interaction session key. The adapter accepts
bounded regular files only within Xcode's temporary `ActionArtifacts` directory,
with the expected operation directory and session prefix. It refuses symlink
reads, copies screenshots and redacted hierarchy text into `ArtifactStore`, then
unlinks only the returned files belonging to its session. Managed copies use the
normal 24-hour TTL and 2-GB cap. Screenshots are not text-redacted. Raw native
errors, session keys, original filenames, thumbnails, and console logs are never
published. Existing UI capture privacy considerations still apply.

Each operation attempts `DeviceInteractionEndSession`, closes its bridge, and
releases its simulator lock, including on failure, cancellation, and orderly
server shutdown. Cleanup runs outside caller cancellation. A native timeout has
an unknown server-side outcome. A lost start response can leave an unknown
session; a lost capture response can leave native temporary files. Those cases
cannot be recovered safely by guessing session keys or deleting shared folders.
Cleanup failures are reported, not silently relabeled as success. If a tap may
have been sent, inspect before deciding whether to tap again. There is no action
retry and no AXe fallback.

## Scope and costs

This pilot enables native inspection and tap without AXe for those two tools.
Per-operation connection, schema checking, and session setup add overhead; there
is no claimed latency improvement. Other gestures, navigation tools, physical
devices, previews, and LLDB continue using their existing implementations.
Native permission approval and installed tool schemas remain requirements.
The native session lock coordinates with ios-mcp's simulator lifecycle tools;
it cannot prevent another app/client or a user from interacting simultaneously.

## Validation record — October 21, 2026

Environment: Xcode 27.1 (27A9275), native server 25320, macOS 26.7, iOS 27.0
Simulator. Xcode 27.2 was not installed or tested.

- A disposable SwiftUI app built, installed, and launched on a dedicated simulator.
  Its increment button and count label have stable accessibility identifiers.
- A separately approved native probe started the exact simulator session,
  captured the app's screenshot and hierarchy (including identifiers and screen
  point hit positions), and ended the session successfully.
- The actual ios-mcp executable reached Xcode's authorization boundary and returned
  a permission error. At that point the Mac was locked. Live adapter inspection,
  identifier/label/coordinate taps, and app-state verification remain pending
  approval of this executable. The native probe capture does not establish those
  behaviors for the adapter.
- Local `swift test` passed 536 enabled tests (including 19 pilot tests and two
  process I/O regressions);
  12 opt-in integration tests were skipped. Deterministic checks cover schema changes, structured/text replies, permission
  failures, timeouts/cancellation, exact-device validation, target ambiguity and
  coordinates, managed captures, unsafe files, cleanup failures, and no AXe
  fallback. These use a fake MCP transport or native service boundary and do not
  substitute for live acceptance.

The initial hosted runs at `2e2f218` exposed cooperative-worker starvation in
`CommandExecutor`: blocking pipe reads delayed cancellation and native MCP
requests until a 60-second child exited. The same eight native transport failures
were reproduced locally with one concurrency worker. Pipe reads now run on
Dispatch threads, and CI retains a combined one-worker check for the command
executor, native MCP transport, and LLDB. Output-draining and launch-failure
checks cover both ordinary and streaming commands.

## Live acceptance recipe

With the final executable approved for a disposable project, boot its dedicated
simulator and launch the app. Use the existing `udid`/session-default inputs:

1. `inspect_ui`: verify expected app, accessibility IDs, and managed artifact files.
2. `tap` by `accessibility_id`, then by `accessibility_label`, then by fractional
   `x`/`y`: verify exactly one increment for each call in subsequent captures.
3. Try an absent identifier and an out-of-window coordinate: verify errors and
   unchanged count, then a successful inspection to establish recovery.
4. Disconnect the client; check that no owned bridge remains and managed captures
   survive session cleanup. Close/remove only the disposable workspace/simulator.

Do not enable this by default until the live checks pass on the supported Xcode
versions. Add other gestures only after their coordinate and failure behavior
has been verified separately.
