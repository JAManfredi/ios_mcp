//
//  NavigationToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
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
