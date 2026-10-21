# Native Xcode MCP compatibility

Author: Jared Manfredi

Checked October 21, 2026 with Xcode 27.1 (27A9275), macOS 26.7,
LLDB 2103.0.34.103, and the native `xcode-tools` server version 25320.
This is a compatibility assessment, not an enabled replacement backend.

## Diagnostics

Run `ios-mcp doctor`. Its native section uses only:

```text
xcrun --find xcodebuild
xcrun --find mcpbridge
xcrun --find mcp-server
xcrun --find lldb-mcp
xcrun mcp-server status --format json
```

The resolved `xcodebuild` path identifies the effective toolchain, including a
`DEVELOPER_DIR` override. Each lookup has a five-second timeout; the status query
has ten seconds. Missing tools, failed queries, and unsupported status formats
are reported without changing the dependency verdict. Cancellation propagates.
Unknown permission state is not treated as disabled or approved.

Doctor does not connect to native servers, call tools, start sessions, open
workspaces, or change permissions. Service state and headless enablement are
separate from authorization of a particular agent and project folder. Tool
schemas require an explicit MCP connection and are not inferred from version
numbers. The normal dependency checks still apply: this machine's installed
axe 1.4.0 failed the existing Xcode 27 minimum-version check.

## Checks and results

| Check | Observed result | What it establishes |
|---|---|---|
| `mcpbridge` initialize and paginated `tools/list` | Passed, 53 tools, MCP protocol 2024-11-05, no open workspace | Native catalog discovery works headlessly; it started the native service on this machine |
| Native UI session on a dedicated temporary simulator | Denied: probe agent not approved; server directed it to open/create a project to request approval | Headless enablement and successful catalog discovery do not authorize UI execution |
| `lldb-mcp` stdio connection | Failed on an existing stale server registration | Binary availability is insufficient for a working connection |
| `lldb-mcp` with an additional owned LLDB server | Failed: multiple servers cannot be selected in this installed version | Automatic discovery cannot safely select the intended debugger here |
| Direct connection to an owned LLDB protocol server | Passed initialize, tools/list, debugger_list, version, invalid command, task-tree-without-process, then version again | Request/reply framing, error propagation, and subsequent-command recovery work without attaching to an app |
| Project discovery with `project.pbxproj` or `project.xcproj` inside `.xcodeproj` | Regression test passes for both | Discovery is independent of the internal configuration filename; this is not a build test of the JSON format |

No native access was granted, existing debugger registrations were left intact,
and no existing app was attached or interacted with. The owned LLDB protocol
server was stopped and its process exited. The temporary simulator was removed.

## UI contract observed on 27.1

The catalog advertises these tools:

- `DeviceInteractionStartSession`: requires `deviceIdentifier` and
  `sessionIdentifier`, supports operation without a workspace, and returns
  `interactionSessionKey`, `deviceUUID`, and `deviceIsSimulator`.
- `DeviceInteractionStartWorkspaceSession`: binds interaction to a workspace
  and enables `DeviceInteractionInstallAndRun`.
- `DeviceInteractionSynthesize`: requires **`interactSessionKey`** (different
  spelling from the start/end tools); optionally accepts `activationBundleId`
  and an `interactionCommand` string. Its advertised outputs include screenshot,
  thumbnail, hierarchy, and console-log file paths plus application state.
- `DeviceInteractionEndSession`: requires `interactionSessionKey`. Explicit
  cleanup is needed because interaction sessions consume resources.

An adapter would need to own the session, validate the returned device UUID
against the requested UDID, keep session keys private, and import returned
artifacts into managed storage. It would also need to translate our identifier
targeting into the native hierarchy/interaction contract. A session start must
not silently select a different device after the native fuzzy identifier match.

The approval failure occurred before UI capture or input. Hierarchy fidelity,
identifier/label targeting, coordinate units, tap, swipe, long press, text/key
input, orientation, and artifact cleanup remain unverified on an app. Do not
remove axe or route existing UI tools through this backend based on the catalog.

## LLDB contract observed on 27.1

The owned server was started with `lldb --no-lldbinit` and
`protocol-server start MCP`. The probe connected only to the localhost URI
returned by that process, initialized MCP 2024-11-05, and queried its catalog.
It advertised **`command` and `debugger_list`**, not the session creation/closure
tools described by current upstream LLDB documentation.

`command` accepts a command string and optional debugger ID/URI. Both an invalid
command and `language swift task tree` without a running process returned text
diagnostics with `isError: true`. A subsequent `version` response contained only
that command's output. No debuggee was started or attached.

The standalone launcher exited with `Failed to connect` for a stale registered
endpoint. With a second owned endpoint present, it exited with
`too many MCP servers running, picking a specific one is not yet implemented`.
Do not delete registrations, select the first debugger, or assume upstream
session APIs exist. A future backend needs explicit ownership/selection and
must preserve command policy, redaction, cancellation, and timeout behavior.
Attach/detach, breakpoints, stopped/running transitions, and debuggee output
remain separate acceptance checks. Keep the existing LLDB backend for now.

## Preview, coverage, and project format

The 27.1 catalog contains `RenderPreview` with `sourceFilePath`, preview index,
variant/localization/canvas overrides, timeout, and workspace selection. It
reports the rendered destination, but exposes no destination-selection input.
`GetCodeCoverage` was absent. Neither capability should be inferred solely from
the executable being present.

Apple's 27.2 release notes describe preview destination selection and
`GetCodeCoverage`. Recheck their actual schemas on 27.2 before implementation;
27.2 was not installed or tested in this assessment. Existing explicit-result
coverage through `xccov` remains useful.

The JSON `.xcproj` configuration lives inside the existing `.xcodeproj` bundle,
so the project scanner needs no new top-level extension. The retained discovery
test intentionally does not parse the configuration contents.

## Next acceptance step

Use an explicitly approved agent and a disposable project/device to verify the
UI behaviors above, including session cleanup on failure and cancellation.
Recheck the LLDB launcher against the installed version's catalog and explicit
session-selection behavior before choosing a transport. These checks are
opt-in because connecting can start services and requesting project access can
show an Xcode approval prompt; they do not belong in ordinary `doctor` or CI.

References: [Apple Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes),
[Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes),
[LLDB MCP documentation](https://lldb.llvm.org/use/mcp.html), and
[Xcode project format](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format).
The observations above come from the installed tools, rather than assuming
that current online documentation describes this exact build.
