//
//  NavigationToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

// MARK: - Test Helpers

private func writeTestGraph(
    nodes: [String: [String: Any]]? = nil,
    edges: [[String: Any]]? = nil
) throws -> String {
    let defaultNodes: [String: [String: Any]] = [
        "home": ["id": "home", "name": "Home", "isTabRoot": true, "deeplinkTemplate": "app://home"],
        "search": ["id": "search", "name": "Search", "isTabRoot": false, "deeplinkTemplate": "app://search"],
        "player": ["id": "player", "name": "Player", "isTabRoot": false],
    ]

    let defaultEdges: [[String: Any]] = [
        [
            "from": "*",
            "to": "home",
            "actions": [["type": "deeplink", "url": "app://home"]],
        ],
        [
            "from": "*",
            "to": "search",
            "actions": [["type": "deeplink", "url": "app://search"]],
        ],
    ]

    let graph: [String: Any] = [
        "version": "1.0",
        "app": "test",
        "nodes": nodes ?? defaultNodes,
        "edges": edges ?? defaultEdges,
    ]

    let data = try JSONSerialization.data(withJSONObject: graph, options: .prettyPrinted)
    let path = NSTemporaryDirectory() + "nav_test_\(UUID().uuidString).json"
    try data.write(to: URL(fileURLWithPath: path))
    return path
}

// MARK: - load_nav_graph

@Suite("load_nav_graph")
struct LoadNavGraphToolTests {

    @Test("Loads graph from explicit path")
    func loadExplicitPath() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator(), videoRecording: MockVideoRecording(), navGraph: NavGraphStore())

        let navGraph = NavGraphStore()
        await registerLoadNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "load_nav_graph",
            arguments: ["path": .string(path)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("v1.0"))
            #expect(result.content.contains("3 nodes"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Returns guidance when file not found")
    func fileNotFound() async throws {
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        await registerLoadNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "load_nav_graph",
            arguments: ["path": .string("/nonexistent/nav_graph.json")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("not available"))
            #expect(result.content.contains("inspect_ui"))
        } else {
            Issue.record("Expected success response with fallback guidance")
        }
    }

    @Test("Returns guidance when no path and no auto-discovery")
    func noPathNoDiscovery() async throws {
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        await registerLoadNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "load_nav_graph",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("No navigation graph found"))
            #expect(result.content.contains("optional"))
        } else {
            Issue.record("Expected success response with guidance")
        }
    }
}

// MARK: - get_nav_graph

@Suite("get_nav_graph")
struct GetNavGraphToolTests {

    @Test("Returns graph summary when loaded")
    func graphSummary() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerGetNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "get_nav_graph",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("NODES"))
            #expect(result.content.contains("home"))
            #expect(result.content.contains("search"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Returns single node detail")
    func singleNode() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerGetNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "get_nav_graph",
            arguments: ["node_id": .string("home")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Home"))
            #expect(result.content.contains("home"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Guides to inspect_ui when no graph loaded")
    func noGraphLoaded() async throws {
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        await registerGetNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "get_nav_graph",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("inspect_ui"))
        } else {
            Issue.record("Expected success response with guidance")
        }
    }
}

// MARK: - navigate_to

@Suite("navigate_to")
struct NavigateToToolTests {

    @Test("Guides to inspect_ui when no graph loaded")
    func noGraphGuidance() async throws {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()

        await registerNavigateToTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "navigate_to",
            arguments: ["target": .string("home")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("inspect_ui"))
        } else {
            Issue.record("Expected success guidance")
        }
    }

    @Test("Reports already at target")
    func alreadyAtTarget() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerNavigateToTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "navigate_to",
            arguments: ["target": .string("home"), "from": .string("home")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Already at target"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors for unknown target node")
    func unknownTarget() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerNavigateToTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "navigate_to",
            arguments: ["target": .string("nonexistent"), "from": .string("home")]
        )

        if case .error(let error) = response {
            #expect(error.message.contains("Unknown target"))
        } else {
            Issue.record("Expected error for unknown target")
        }
    }

    @Test("Executes deeplink action for navigation")
    func executesDeeplinkAction() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerNavigateToTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "navigate_to",
            arguments: [
                "target": .string("search"),
                "from": .string("home"),
                "settle_ms": .int(0),
            ]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Navigation complete"))
            let args = await capture.lastArgs
            #expect(args.contains("openurl"))
            #expect(args.contains("app://search"))
        } else {
            Issue.record("Expected success response")
        }
    }
}

// MARK: - where_am_i

@Suite("where_am_i")
struct WhereAmIToolTests {

    @Test("Guides to inspect_ui when no graph loaded")
    func noGraphGuidance() async throws {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()

        await registerWhereAmITool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "where_am_i",
            arguments: [:]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("inspect_ui"))
        } else {
            Issue.record("Expected success guidance")
        }
    }
}

// MARK: - save_nav_graph

@Suite("save_nav_graph")
struct SaveNavGraphToolTests {

    @Test("Saves graph to specified path")
    func savesToPath() async throws {
        let loadPath = try writeTestGraph()
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        try await navGraph.load(from: loadPath)

        await registerSaveNavGraphTool(with: registry, navGraph: navGraph)

        let savePath = NSTemporaryDirectory() + "saved_\(UUID().uuidString).json"
        let response = try await registry.callTool(
            name: "save_nav_graph",
            arguments: ["path": .string(savePath)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains(savePath))
            #expect(FileManager.default.fileExists(atPath: savePath))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Errors when no graph loaded")
    func noGraphLoaded() async throws {
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        await registerSaveNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(
            name: "save_nav_graph",
            arguments: [:]
        )

        if case .error(let error) = response {
            #expect(error.message.contains("No navigation graph loaded"))
        } else {
            Issue.record("Expected error response")
        }
    }
}

// MARK: - tag_screen

@Suite("tag_screen")
struct TagScreenToolTests {

    @Test("Errors when no graph loaded")
    func noGraphLoaded() async throws {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()

        await registerTagScreenTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "tag_screen",
            arguments: ["node_id": .string("home")]
        )

        if case .error(let error) = response {
            #expect(error.message.contains("No navigation graph loaded"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Skips when fingerprint already exists")
    func skipsExisting() async throws {
        let path = try writeTestGraph(nodes: [
            "home": [
                "id": "home", "name": "Home", "isTabRoot": true,
                "fingerprint": ["accessibilityId": "ExistingId"],
            ],
        ])
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerTagScreenTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "tag_screen",
            arguments: ["node_id": .string("home")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("already has a fingerprint"))
        } else {
            Issue.record("Expected success with skip message")
        }
    }

    @Test("Errors for unknown node")
    func unknownNode() async throws {
        let path = try writeTestGraph()
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)

        await registerTagScreenTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(
            name: "tag_screen",
            arguments: ["node_id": .string("nonexistent")]
        )

        if case .error(let error) = response {
            #expect(error.message.contains("Unknown node"))
        } else {
            Issue.record("Expected error for unknown node")
        }
    }
}

// MARK: - Fingerprint capture and edge selection

/// `axe describe-ui` output in the shape AXe actually emits: role under
/// `role`, visible static text under `AXLabel`, `AXValue` usually null.
private let axeTreeJSON = """
[{
  "role": "AXApplication", "type": "Application", "AXUniqueId": null, "AXLabel": "App", "AXValue": null,
  "children": [
    {"role": "AXGroup", "type": "Group", "AXUniqueId": "TabBar", "AXLabel": null, "AXValue": null, "children": []},
    {"role": "AXGroup", "type": "Group", "AXUniqueId": "SearchScreenRoot", "AXLabel": null, "AXValue": null, "children": [
      {"role": "AXStaticText", "type": "StaticText", "AXUniqueId": null, "AXLabel": "Search", "AXValue": null, "children": []},
      {"role": "AXStaticText", "type": "StaticText", "AXUniqueId": null, "AXLabel": "Trending", "AXValue": null, "children": []},
      {"role": "AXStaticText", "type": "StaticText", "AXUniqueId": null, "AXLabel": "Trending", "AXValue": null, "children": []},
      {"role": "AXButton", "type": "Button", "AXUniqueId": "TabBar", "AXLabel": "Home", "AXValue": null, "children": []}
    ]}
  ]
}]
"""

private let axeAvailable: Bool = {
    if case .success = resolveAxePath() { return true }
    return false
}()

/// Executor that answers `describe-ui` with `tree` and records every call.
private func recordingExecutor(tree: String = axeTreeJSON, calls: AllCallCapture) -> MockCommandExecutor {
    MockCommandExecutor { _, args in
        await calls.capture(args)
        let stdout = args.contains("describe-ui") ? tree : ""
        return CommandResult(stdout: stdout, stderr: "", exitCode: 0)
    }
}

@Suite("ScreenSnapshot")
struct ScreenSnapshotTests {

    @Test("Parses AXe's role and AXLabel keys, deduplicating IDs")
    func parsesAxeShape() throws {
        let snapshot = try #require(ScreenSnapshot.parse(axeTreeJSON))
        #expect(snapshot.accessibilityIds == ["TabBar", "SearchScreenRoot"])
        #expect(snapshot.staticTexts == ["Search", "Trending", "Trending"])
        #expect(snapshot.dominantStaticText == "Trending")
    }

    @Test("Dominant text ties go to the first text seen")
    func dominantTextTieBreak() throws {
        let json = """
        [{"role": "AXStaticText", "AXLabel": "B", "children": []},
         {"role": "AXStaticText", "AXLabel": "A", "children": []}]
        """
        #expect(ScreenSnapshot.parse(json)?.dominantStaticText == "B")
    }

    @Test("Rejects non-JSON output")
    func rejectsGarbage() {
        #expect(ScreenSnapshot.parse("Error: no simulator") == nil)
    }
}

@Suite("navigate_to edge selection")
struct NavigateToEdgeSelectionTests {

    private func searchGraph() throws -> String {
        try writeTestGraph(edges: [
            ["id": "search", "from": "*", "to": "search", "actions": [["type": "deeplink", "url": "app://search"]]],
            ["id": "searchWithQuery", "from": "*", "to": "search", "preconditions": ["logged_in"],
             "actions": [["type": "deeplink", "url": "app://search/{term}"]]],
            ["from": "*", "to": "home", "actions": [["type": "deeplink", "url": "app://home"]]],
        ])
    }

    private func navigate(_ arguments: [String: Value], graph: String) async throws -> (ToolResponse, [[String]]) {
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let calls = AllCallCapture()
        let navGraph = NavGraphStore()
        try await navGraph.load(from: graph)
        await registerNavigateToTool(with: registry, session: session, executor: recordingExecutor(calls: calls), navGraph: navGraph, validator: testValidator())

        var args = arguments
        args["settle_ms"] = .int(0)
        let response = try await registry.callTool(name: "navigate_to", arguments: args)
        return (response, await calls.allArgs)
    }

    @Test("Uses the parameterized edge when its parameter is supplied, percent-encoding the value")
    func picksEdgeByParameters() async throws {
        let (response, calls) = try await navigate([
            "target": .string("search"), "from": .string("home"),
            "parameters": .string(#"{"term": "summer sale/deals"}"#),
        ], graph: try searchGraph())

        guard case .success(let result) = response else { Issue.record("Expected success: \(response)"); return }
        #expect(calls.last?.contains("app://search/summer%20sale%2Fdeals") == true)
        #expect(result.content.contains("Preconditions (not checked): logged_in"))
    }

    @Test("'via' selects an edge by ID")
    func viaSelectsEdge() async throws {
        let (response, calls) = try await navigate([
            "target": .string("search"), "from": .string("home"), "via": .string("search"),
            "parameters": .string(#"{"term": "x"}"#),
        ], graph: try searchGraph())

        guard case .success = response else { Issue.record("Expected success: \(response)"); return }
        #expect(calls.last?.contains("app://search") == true)
    }

    @Test("'via' runs an in-tab edge even when already on the target node")
    func viaRunsSameNodeEdge() async throws {
        let graph = try writeTestGraph(edges: [
            ["from": "*", "to": "home", "actions": [["type": "deeplink", "url": "app://home"]]],
            ["id": "pools", "from": "*", "to": "home", "navMode": "in_tab", "actions": [["type": "deeplink", "url": "app://pools"]]],
        ])

        let (withVia, viaCalls) = try await navigate([
            "target": .string("home"), "from": .string("home"), "via": .string("pools"),
        ], graph: graph)
        guard case .success = withVia else { Issue.record("Expected success: \(withVia)"); return }
        #expect(viaCalls.last?.contains("app://pools") == true)

        let (withoutVia, plainCalls) = try await navigate([
            "target": .string("home"), "from": .string("home"),
        ], graph: graph)
        guard case .success(let result) = withoutVia else { Issue.record("Expected success"); return }
        #expect(result.content.contains("Already at target"))
        #expect(plainCalls.isEmpty)
    }

    @Test("Unknown 'via' lists the available edges")
    func unknownVia() async throws {
        let (response, calls) = try await navigate([
            "target": .string("search"), "from": .string("home"), "via": .string("nope"),
        ], graph: try searchGraph())

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.message.contains("No edge 'nope'"))
        #expect(error.details?.contains("searchWithQuery") == true)
        #expect(calls.isEmpty)
    }

    @Test("Malformed parameters JSON is an error, not silently ignored")
    func malformedParameters() async throws {
        let (response, calls) = try await navigate([
            "target": .string("search"), "from": .string("home"), "parameters": .string("{term: x"),
        ], graph: try searchGraph())

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.code == .invalidInput)
        #expect(calls.isEmpty)
    }

    @Test("Booleans and numbers stringify as JSON values")
    func scalarParameters() throws {
        guard case .success(let params) = parseParameters(#"{"isLive": true, "id": 12345, "ratio": 1.5}"#) else {
            Issue.record("Expected success"); return
        }
        #expect(params == ["isLive": "true", "id": "12345", "ratio": "1.5"])
        #expect(percentEncodedPathValue("already%2Fencoded") == "already%2Fencoded")
    }

    @Test("type_text taps the target, then runs `axe type`", .enabled(if: axeAvailable))
    func typeTextUsesAxeType() async throws {
        let graph = try writeTestGraph(edges: [
            ["from": "*", "to": "search", "actions": [
                ["type": "type_text", "text": "{term}", "target": ["accessibilityId": "SearchField"]],
            ]],
        ])
        let (response, calls) = try await navigate([
            "target": .string("search"), "from": .string("home"), "parameters": .string(#"{"term": "Lakers"}"#),
        ], graph: graph)

        guard case .success = response else { Issue.record("Expected success: \(response)"); return }
        #expect(calls.count == 2)
        #expect(calls.first?.starts(with: ["tap", "--udid", "AAAA-1111", "--id", "SearchField"]) == true)
        #expect(calls.last == ["type", "Lakers", "--udid", "AAAA-1111"])
    }

    @Test("Detects the starting node from a live fingerprint", .enabled(if: axeAvailable))
    func detectsOrigin() async throws {
        let graph = try writeTestGraph(nodes: [
            "home": ["id": "home", "name": "Home", "isTabRoot": true],
            "search": ["id": "search", "name": "Search", "isTabRoot": false, "fingerprint": ["accessibilityId": "SearchScreenRoot"]],
        ])
        let (response, _) = try await navigate(["target": .string("search")], graph: graph)

        guard case .success(let result) = response else { Issue.record("Expected success: \(response)"); return }
        #expect(result.content.contains("Already at target"))
    }
}

@Suite("Fingerprint tools", .enabled(if: axeAvailable))
struct FingerprintToolTests {

    @Test("where_am_i matches static text from AXLabel")
    func whereAmIMatchesStaticText() async throws {
        let path = try writeTestGraph(nodes: [
            "search": ["id": "search", "name": "Search", "isTabRoot": false, "fingerprint": ["dominantStaticText": "Trending"]],
        ])
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)
        await registerWhereAmITool(with: registry, session: session, executor: recordingExecutor(calls: AllCallCapture()), navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(name: "where_am_i", arguments: [:])
        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("Current screen: Search (search)"))
        #expect(result.content.contains("Confidence: medium"))
    }

    @Test("where_am_i reports ambiguity instead of guessing")
    func whereAmIAmbiguous() async throws {
        let path = try writeTestGraph(nodes: [
            "home": ["id": "home", "name": "Home", "isTabRoot": true, "fingerprint": ["accessibilityId": "TabBar"]],
            "search": ["id": "search", "name": "Search", "isTabRoot": false, "fingerprint": ["accessibilityId": "TabBar"]],
        ])
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)
        await registerWhereAmITool(with: registry, session: session, executor: recordingExecutor(calls: AllCallCapture()), navGraph: navGraph, validator: testValidator())

        let response = try await registry.callTool(name: "where_am_i", arguments: [:])
        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("Ambiguous: 2 nodes"))
        #expect(result.content.contains("home (Home)"))
        #expect(result.content.contains("search (Search)"))
    }

    private func tag(_ arguments: [String: Value], nodes: [String: [String: Any]]) async throws -> (ToolResponse, NavGraphStore) {
        let registry = ToolRegistry()
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "AAAA-1111")
        let navGraph = NavGraphStore()
        try await navGraph.load(from: try writeTestGraph(nodes: nodes))
        await registerTagScreenTool(with: registry, session: session, executor: recordingExecutor(calls: AllCallCapture()), navGraph: navGraph, validator: testValidator())
        return (try await registry.callTool(name: "tag_screen", arguments: arguments), navGraph)
    }

    @Test("tag_screen skips IDs other nodes already use and records static text")
    func tagSkipsClaimedIds() async throws {
        let (response, navGraph) = try await tag(["node_id": .string("search")], nodes: [
            "home": ["id": "home", "name": "Home", "isTabRoot": true, "fingerprint": ["accessibilityId": "TabBar"]],
            "search": ["id": "search", "name": "Search", "isTabRoot": false],
        ])

        guard case .success(let result) = response else { Issue.record("Expected success: \(response)"); return }
        let fingerprint = await navGraph.getNode("search")?.fingerprint
        #expect(fingerprint?.accessibilityId == "SearchScreenRoot")
        #expect(fingerprint?.dominantStaticText == "Trending")
        #expect(result.content.contains("(auto-selected)"))
    }

    @Test("tag_screen uses an explicit accessibility_id")
    func tagExplicitId() async throws {
        let (response, navGraph) = try await tag(
            ["node_id": .string("search"), "accessibility_id": .string("SearchScreenRoot"), "static_text": .string("Search")],
            nodes: ["search": ["id": "search", "name": "Search", "isTabRoot": false]]
        )

        guard case .success = response else { Issue.record("Expected success: \(response)"); return }
        let fingerprint = await navGraph.getNode("search")?.fingerprint
        #expect(fingerprint?.accessibilityId == "SearchScreenRoot")
        #expect(fingerprint?.dominantStaticText == "Search")
    }

    @Test("tag_screen rejects an accessibility_id that isn't on screen")
    func tagRejectsMissingId() async throws {
        let (response, navGraph) = try await tag(
            ["node_id": .string("search"), "accessibility_id": .string("Typo")],
            nodes: ["search": ["id": "search", "name": "Search", "isTabRoot": false]]
        )

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.message.contains("not on the current screen"))
        #expect(await navGraph.getNode("search")?.fingerprint == nil)
    }
}

@Suite("get_nav_graph edge details")
struct GetNavGraphEdgeDetailTests {

    @Test("Edge listing shows ID, URL, parameters, and preconditions")
    func edgeDetails() async throws {
        let path = try writeTestGraph(edges: [
            ["id": "searchWithQuery", "from": "*", "to": "search", "navMode": "push", "preconditions": ["logged_in"],
             "parameters": [["name": "term", "type": "string", "required": true, "exampleValue": "shoes"]],
             "actions": [["type": "deeplink", "url": "app://search/{term}/{page}"]]],
        ])
        let registry = ToolRegistry()
        let navGraph = NavGraphStore()
        try await navGraph.load(from: path)
        await registerGetNavGraphTool(with: registry, navGraph: navGraph)

        let response = try await registry.callTool(name: "get_nav_graph", arguments: ["include_edges": .bool(true)])
        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("* → search  [searchWithQuery] (push)"))
        #expect(result.content.contains("deeplink app://search/{term}/{page}"))
        #expect(result.content.contains("params: term: string (e.g. shoes)"))
        #expect(result.content.contains("undeclared placeholders: page"))
        #expect(result.content.contains("requires: logged_in"))
    }
}
