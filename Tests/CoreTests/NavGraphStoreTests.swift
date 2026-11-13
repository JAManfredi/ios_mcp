//
//  NavGraphStoreTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("NavGraphStore")
struct NavGraphStoreTests {

    // MARK: - Test Graph Helper

    private func writeTestGraph(
        nodes: [String: [String: Any]] = [:],
        edges: [[String: Any]] = [],
        commands: [[String: Any]]? = nil
    ) throws -> String {
        let defaultNodes: [String: [String: Any]] = nodes.isEmpty ? [
            "home": ["id": "home", "name": "Home", "isTabRoot": true],
            "search": ["id": "search", "name": "Search", "isTabRoot": false],
            "player": ["id": "player", "name": "Player", "isTabRoot": false],
        ] : nodes

        let defaultEdges: [[String: Any]] = edges.isEmpty ? [
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
            [
                "from": "home",
                "to": "player",
                "actions": [["type": "tap", "target": ["accessibilityId": "player_button"]]],
            ],
        ] : edges

        var graph: [String: Any] = [
            "version": "1.0",
            "app": "test",
            "nodes": defaultNodes,
            "edges": defaultEdges,
        ]

        if let commands {
            graph["commands"] = commands
        }

        let data = try JSONSerialization.data(withJSONObject: graph, options: .prettyPrinted)
        let path = NSTemporaryDirectory() + "test_nav_graph_\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - Loading

    @Test("Loads graph from file")
    func loadFromFile() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let loaded = await store.isLoaded()
        #expect(loaded)

        let graph = await store.getGraph()
        #expect(graph?.version == "1.0")
        #expect(graph?.app == "test")
        #expect(graph?.nodes.count == 3)
        #expect(graph?.edges.count == 3)
    }

    @Test("Reports not loaded before load")
    func notLoadedInitially() async {
        let store = NavGraphStore()
        let loaded = await store.isLoaded()
        #expect(!loaded)
    }

    @Test("Unload clears graph")
    func unload() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        await store.unload()
        let loaded = await store.isLoaded()
        #expect(!loaded)
    }

    @Test("Throws on invalid JSON")
    func invalidJSON() async {
        let path = NSTemporaryDirectory() + "bad_\(UUID().uuidString).json"
        try? "not json".write(toFile: path, atomically: true, encoding: .utf8)

        let store = NavGraphStore()
        do {
            try await store.load(from: path)
            Issue.record("Expected error for invalid JSON")
        } catch {
            // Expected
        }
    }

    // MARK: - Queries

    @Test("Gets node by ID")
    func getNode() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let home = await store.getNode("home")
        #expect(home?.name == "Home")
        #expect(home?.isTabRoot == true)

        let missing = await store.getNode("nonexistent")
        #expect(missing == nil)
    }

    @Test("Gets all nodes")
    func allNodes() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let nodes = await store.allNodes()
        #expect(nodes.count == 3)
    }

    @Test("Gets edges from node")
    func edgesFrom() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        // "home" has one direct edge to "player", plus 2 wildcard edges
        let edges = await store.edges(from: "home")
        #expect(edges.count == 3)
    }

    @Test("Gets edges to node")
    func edgesTo() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let edges = await store.edges(to: "home")
        #expect(edges.count == 1)
    }

    // MARK: - Pathfinding

    @Test("Finds direct path via wildcard")
    func directPath() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let route = await store.shortestPath(from: "search", to: "home")
        #expect(route?.count == 1)
        #expect(route?.first?.to == "home")
    }

    @Test("Finds multi-hop path")
    func multiHopPath() async throws {
        let path = try writeTestGraph(
            nodes: [
                "a": ["id": "a", "name": "A", "isTabRoot": false],
                "b": ["id": "b", "name": "B", "isTabRoot": false],
                "c": ["id": "c", "name": "C", "isTabRoot": false],
            ],
            edges: [
                ["from": "a", "to": "b", "actions": [["type": "tap", "target": ["accessibilityId": "b_btn"]]]],
                ["from": "b", "to": "c", "actions": [["type": "tap", "target": ["accessibilityId": "c_btn"]]]],
            ]
        )
        let store = NavGraphStore()
        try await store.load(from: path)

        let route = await store.shortestPath(from: "a", to: "c")
        #expect(route?.count == 2)
    }

    @Test("Returns nil for unreachable node")
    func unreachablePath() async throws {
        let path = try writeTestGraph(
            nodes: [
                "a": ["id": "a", "name": "A", "isTabRoot": false],
                "b": ["id": "b", "name": "B", "isTabRoot": false],
            ],
            edges: []
        )
        let store = NavGraphStore()
        try await store.load(from: path)

        let route = await store.shortestPath(from: "a", to: "b")
        #expect(route == nil)
    }

    @Test("Returns nil for unknown target")
    func unknownTarget() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let route = await store.shortestPath(from: "home", to: "nonexistent")
        #expect(route == nil)
    }

    // MARK: - Fingerprint Matching

    @Test("Matches by accessibility ID")
    func matchByAccessibilityId() async throws {
        let path = try writeTestGraph(nodes: [
            "home": [
                "id": "home", "name": "Home", "isTabRoot": true,
                "fingerprint": ["accessibilityId": "HomeScreen"],
            ],
        ])
        let store = NavGraphStore()
        try await store.load(from: path)

        let match = await store.matchFingerprint(
            accessibilityIds: ["HomeScreen", "OtherThing"],
            staticTexts: []
        )
        #expect(match?.nodeId == "home")
        #expect(match?.confidence == "high")
    }

    @Test("Matches by dominant text when no ID match")
    func matchByDominantText() async throws {
        let path = try writeTestGraph(nodes: [
            "home": [
                "id": "home", "name": "Home", "isTabRoot": true,
                "fingerprint": ["dominantStaticText": "Welcome Back"],
            ],
        ])
        let store = NavGraphStore()
        try await store.load(from: path)

        let match = await store.matchFingerprint(
            accessibilityIds: ["UnrelatedId"],
            staticTexts: ["Welcome Back"]
        )
        #expect(match?.nodeId == "home")
        #expect(match?.confidence == "medium")
    }

    @Test("Returns nil when no match")
    func noFingerprintMatch() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let match = await store.matchFingerprint(
            accessibilityIds: ["SomethingRandom"],
            staticTexts: ["Unknown Text"]
        )
        #expect(match == nil)
    }

    // MARK: - Mutation

    @Test("Sets fingerprint on node without existing fingerprint")
    func setFingerprint() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let fingerprint = NavGraphStore.NodeFingerprint(accessibilityId: "HomeRoot")
        let result = await store.setFingerprint(nodeId: "home", fingerprint: fingerprint)
        #expect(result)

        let node = await store.getNode("home")
        #expect(node?.fingerprint?.accessibilityId == "HomeRoot")
    }

    @Test("Skips overwrite when force is false")
    func skipOverwrite() async throws {
        let path = try writeTestGraph(nodes: [
            "home": [
                "id": "home", "name": "Home", "isTabRoot": true,
                "fingerprint": ["accessibilityId": "ExistingId"],
            ],
        ])
        let store = NavGraphStore()
        try await store.load(from: path)

        let newFingerprint = NavGraphStore.NodeFingerprint(accessibilityId: "NewId")
        let result = await store.setFingerprint(nodeId: "home", fingerprint: newFingerprint, force: false)
        #expect(!result)

        let node = await store.getNode("home")
        #expect(node?.fingerprint?.accessibilityId == "ExistingId")
    }

    @Test("Overwrites when force is true")
    func forceOverwrite() async throws {
        let path = try writeTestGraph(nodes: [
            "home": [
                "id": "home", "name": "Home", "isTabRoot": true,
                "fingerprint": ["accessibilityId": "ExistingId"],
            ],
        ])
        let store = NavGraphStore()
        try await store.load(from: path)

        let newFingerprint = NavGraphStore.NodeFingerprint(accessibilityId: "NewId")
        let result = await store.setFingerprint(nodeId: "home", fingerprint: newFingerprint, force: true)
        #expect(result)

        let node = await store.getNode("home")
        #expect(node?.fingerprint?.accessibilityId == "NewId")
    }

    @Test("Returns false for unknown node")
    func setFingerprintUnknownNode() async throws {
        let path = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: path)

        let fingerprint = NavGraphStore.NodeFingerprint(accessibilityId: "Test")
        let result = await store.setFingerprint(nodeId: "nonexistent", fingerprint: fingerprint)
        #expect(!result)
    }

    // MARK: - Persistence

    @Test("Saves graph to file")
    func saveGraph() async throws {
        let loadPath = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: loadPath)

        let savePath = NSTemporaryDirectory() + "saved_\(UUID().uuidString).json"
        try await store.save(to: savePath)

        let data = try Data(contentsOf: URL(fileURLWithPath: savePath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["version"] as? String == "1.0")
        #expect((json?["nodes"] as? [String: Any])?.count == 3)
    }

    @Test("Saves to original path by default")
    func saveToOriginalPath() async throws {
        let loadPath = try writeTestGraph()
        let store = NavGraphStore()
        try await store.load(from: loadPath)

        // Mutate and save
        let fingerprint = NavGraphStore.NodeFingerprint(accessibilityId: "Added")
        await store.setFingerprint(nodeId: "home", fingerprint: fingerprint)
        try await store.save()

        // Reload and verify
        let store2 = NavGraphStore()
        try await store2.load(from: loadPath)
        let node = await store2.getNode("home")
        #expect(node?.fingerprint?.accessibilityId == "Added")
    }

    @Test("Save preserves fields the model doesn't decode")
    func savePreservesUnknownFields() async throws {
        let graph: [String: Any] = [
            "version": "3.0",
            "app": "test",
            "generatedFrom": ["commitSha": "abc123"],
            "nodes": [
                "home": ["id": "home", "name": "Home", "isTabRoot": true, "stateCase": "home(Home.State)"],
            ],
            "edges": [
                ["id": "home", "from": "*", "to": "home", "navMode": "tab_switch", "customKey": 1,
                 "actions": [["type": "deeplink", "url": "app://home"]]],
            ],
        ]
        let loadPath = NSTemporaryDirectory() + "raw_\(UUID().uuidString).json"
        try JSONSerialization.data(withJSONObject: graph).write(to: URL(fileURLWithPath: loadPath))

        let store = NavGraphStore()
        try await store.load(from: loadPath)
        await store.setFingerprint(nodeId: "home", fingerprint: .init(accessibilityId: "HomeRoot"))
        try await store.save()

        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: loadPath))) as? [String: Any]
        let home = (saved?["nodes"] as? [String: Any])?["home"] as? [String: Any]
        let edge = (saved?["edges"] as? [[String: Any]])?.first
        #expect((saved?["generatedFrom"] as? [String: Any])?["commitSha"] as? String == "abc123")
        #expect(home?["stateCase"] as? String == "home(Home.State)")
        #expect((home?["fingerprint"] as? [String: Any])?["accessibilityId"] as? String == "HomeRoot")
        #expect(edge?["customKey"] as? Int == 1)
        #expect(edge?["navMode"] as? String == "tab_switch")
    }

    // MARK: - Edge Selection

    private func parallelSearchEdgesGraph() throws -> String {
        try writeTestGraph(edges: [
            ["id": "search", "from": "*", "to": "search", "actions": [["type": "deeplink", "url": "app://search"]]],
            ["id": "searchWithQuery", "from": "*", "to": "search", "actions": [["type": "deeplink", "url": "app://search/{term}"]]],
        ])
    }

    @Test("Prefers the edge that uses supplied parameters")
    func prefersParameterizedEdgeWhenSupplied() async throws {
        let store = NavGraphStore()
        try await store.load(from: try parallelSearchEdgesGraph())

        let withTerm = await store.shortestPath(from: "home", to: "search", providedParameters: ["term"])
        #expect(withTerm?.first?.id == "searchWithQuery")

        let without = await store.shortestPath(from: "home", to: "search")
        #expect(without?.first?.id == "search")
    }

    @Test("Prefers a resolvable edge over one with missing placeholders")
    func prefersResolvableEdge() async throws {
        let store = NavGraphStore()
        try await store.load(from: try writeTestGraph(edges: [
            ["id": "byId", "from": "*", "to": "search", "actions": [["type": "deeplink", "url": "app://search/{term}"]]],
            ["id": "plain", "from": "*", "to": "search", "actions": [["type": "deeplink", "url": "app://search"]]],
        ]))

        let route = await store.shortestPath(from: "home", to: "search")
        #expect(route?.first?.id == "plain")
    }

    @Test("Edge selectors match by ID or exact deeplink template")
    func edgeSelectorMatching() async throws {
        let store = NavGraphStore()
        try await store.load(from: try parallelSearchEdgesGraph())
        let edges = await store.directEdges(from: "home", to: "search")

        #expect(edges.first { $0.matches(selector: "searchWithQuery") }?.id == "searchWithQuery")
        #expect(edges.first { $0.matches(selector: "app://search/{term}") }?.id == "searchWithQuery")
        #expect(edges.first { $0.matches(selector: "app://search/") } == nil)
    }

    @Test("Extracts template placeholders")
    func placeholderParsing() {
        #expect(NavGraphStore.placeholders(in: "app://sport/{sportId}/league/{leagueId}") == ["sportId", "leagueId"])
        #expect(NavGraphStore.placeholders(in: "app://home").isEmpty)
        #expect(NavGraphStore.placeholders(in: "app://broken/{open").isEmpty)
    }

    // MARK: - Fingerprint Ambiguity

    @Test("Reports ambiguity when several nodes share a fingerprint ID")
    func ambiguousFingerprint() async throws {
        let path = try writeTestGraph(nodes: [
            "league": ["id": "league", "name": "League", "isTabRoot": false, "fingerprint": ["accessibilityId": "TabBar"]],
            "event": ["id": "event", "name": "Event", "isTabRoot": false, "fingerprint": ["accessibilityId": "TabBar"]],
            "home": ["id": "home", "name": "Home", "isTabRoot": true, "fingerprint": ["dominantStaticText": "Welcome"]],
        ])
        let store = NavGraphStore()
        try await store.load(from: path)

        let matches = await store.fingerprintMatches(accessibilityIds: ["TabBar"], staticTexts: ["Welcome"])
        #expect(matches.map(\.nodeId) == ["event", "league", "home"])
        #expect(matches.map(\.confidence) == ["high", "high", "medium"])

        let single = await store.matchFingerprint(accessibilityIds: ["TabBar"], staticTexts: [])
        #expect(single == nil)

        let claimed = await store.fingerprintIdsClaimed(excluding: "league")
        #expect(claimed == ["TabBar"])
    }
}
