# Native UI pilot

Author: Jared Manfredi

`--ui-backend auto|native|axe` selects the backend for `inspect_ui` and `tap`.
The default remains `axe`. The original `--native-ui-workspace` option alone
still selects strict native mode. With `auto` or `native`, that path overrides
session defaults; otherwise each operation snapshots `workspace`, then `project`.
An absent context permits AXe selection only in `auto`; a malformed/stale path
is an error. `.xcodeproj` and `.xcworkspace` are supported.

In `auto`, an `xcrun --find mcpbridge` lookup and bounded native catalog check
precede all native tool execution. With a project configured, only a confirmed
missing binary or incompatible catalog permits AXe selection. Unexpected lookup/connection errors, cancellation,
permission denial, and every failure after catalog selection remain errors.
There is no action replay. No capability decision is cached across operations:
session project changes take effect on the next call, and the existing connection
is reused from discovery through native execution. Automatic selection can start
the native service and request normal project authorization; it never grants it.

## Behavior and ownership

Each native operation connects an owned `xcrun mcpbridge`, checks the required tool
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
retry or fallback after native execution begins.

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
- After the user approved the actual ios-mcp executable, live acceptance passed
  at `6a5f418`. Inspection returned the expected app and accessibility IDs. Taps
  by identifier, label, and fractional coordinates `(201.1, 451.3)` advanced the
  counter from 0 to 1 to 2 to 3. Both the returned capture and a fresh inspection
  confirmed exactly one increment per call.
- An absent identifier and out-of-window coordinates returned errors. Subsequent
  inspections succeeded and still showed 3. All 18 managed files from nine
  captures survived session cleanup and client disconnect. The server exited
  normally, and neither it nor its owned bridge remained running. The disposable
  workspace was closed and its simulator removed after validation.
- Startup was not immediate: the first simulator launch and direct screenshot
  stalled, and native capture failed. Restarting only the disposable simulator
  restored app launch. The successful run's first inspection took about 60
  seconds; subsequent calls took about 1–5 seconds. These are observations from
  one run, not a latency benchmark or a performance improvement claim.
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

## Automatic selection validation — October 21, 2026

The selection update preserves the AXe default and adds explicit `auto`, `native`,
and `axe` modes. It reuses the native connection after capability discovery;
it does not add a second bridge or retry an action with another backend.

- Local `swift test`: 547 enabled tests passed; 12 opt-in integration tests were
  skipped. All 22 retained process I/O, native transport, LLDB, and backend
  selection tests also passed together with one concurrency worker. Selection
  tests cover missing binaries, incompatible catalogs, unknown/denied preflight,
  project changes, forced modes, cancellation/shutdown, and post-selection errors.
- On Xcode 27.1 and iOS 27.0, `auto` selected native using only the session's
  project default. Three tap modes advanced the counter once each (0 → 1 → 2 → 3).
  Invalid targets failed without mutation; sheet open/close and navigation/return
  passed. A native capture confirmed text entered by AXe, and a native capture
  confirmed AXe scrolling moved the scroll bar from 0% to 19%.
- Clearing session defaults selected AXe and reported the missing project
  context. Native inspection and taps also passed in landscape; portrait was
  restored afterward. The workspace-only option still selected strict native
  mode, while strict native without project context returned an error.
- AXe 1.8.0 was tested from an isolated release download; the installed AXe was
  not changed. Initial AXe inspection attempts timed out creating its remote
  automation session. Later inspection, typing, and scrolling succeeded. In a
  separate forced-AXe run after relaunching the fixture app, the first identifier
  tap reported success but the counter remained 0. That comparison stopped at
  the failed assertion; it was not relabeled as passing. A subsequent native tap
  incremented the counter correctly. No automatic action retry was introduced.

These checks exercise a broader disposable SwiftUI fixture, not a production
app or a controlled latency benchmark. Missing-native compatibility was tested
deterministically; only Xcode 27.1 is installed locally. The AXe no-op and startup
timeouts remain observations to investigate, not problems hidden by fallback.
Keep automatic selection opt-in while gathering real-app and older-Xcode evidence.

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

The live checks pass on this Xcode 27.1 setup. Keep the pilot opt-in until the
supported Xcode versions and broader app/device cases have been exercised.
Cancellation and timeout cleanup remain covered by deterministic tests, not
live fault injection. Add other gestures only after their coordinate and
failure behavior has been verified separately.
