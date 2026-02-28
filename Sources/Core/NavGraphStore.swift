//
//  NavGraphStore.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Loads, holds, and queries a navigation graph.
///
/// The graph is a JSON file supplied by the consuming project that describes
/// screens (nodes), transitions (edges), and the actions needed to traverse
/// them. This actor provides BFS pathfinding and fingerprint matching against
/// the loaded graph.
public actor NavGraphStore {

    // MARK: - Graph Model Types

    public struct NavGraph: Codable, Sendable {
        public let version: String
        public let app: String
        public var nodes: [String: NavNode]
        public let edges: [NavEdge]
        public let commands: [NavCommand]?
    }

    public struct NavNode: Codable, Sendable {
        public let id: String
        public let name: String
        public let isTabRoot: Bool
        public let supportedTabs: [String]?
        public let isCMSDriven: Bool?
        public let deeplinkTemplate: String?
        public let subTabs: [SubTab]?
        public let fingerprint: NodeFingerprint?
        public let validated: Bool?

        public init(
            id: String,
            name: String,
            isTabRoot: Bool,
            supportedTabs: [String]? = nil,
            isCMSDriven: Bool? = nil,
            deeplinkTemplate: String? = nil,
            subTabs: [SubTab]? = nil,
            fingerprint: NodeFingerprint? = nil,
            validated: Bool? = nil
        ) {
            self.id = id
            self.name = name
            self.isTabRoot = isTabRoot
            self.supportedTabs = supportedTabs
            self.isCMSDriven = isCMSDriven
            self.deeplinkTemplate = deeplinkTemplate
            self.subTabs = subTabs
            self.fingerprint = fingerprint
            self.validated = validated
        }
    }

    public struct SubTab: Codable, Sendable {
        public let id: String
        public let name: String
        public let deeplinkTemplate: String
        public let parameters: [EdgeParameter]?
    }

    public struct NodeFingerprint: Codable, Sendable {
        public let accessibilityId: String?
        public let hierarchyHash: String?
        public let dominantStaticText: String?

        public init(
            accessibilityId: String? = nil,
            hierarchyHash: String? = nil,
            dominantStaticText: String? = nil
        ) {
            self.accessibilityId = accessibilityId
            self.hierarchyHash = hierarchyHash
            self.dominantStaticText = dominantStaticText
        }
    }

    public struct NavEdge: Codable, Sendable {
        public let from: String
        public let to: String?
        public let actions: [EdgeAction]
        public let parameters: [EdgeParameter]?
        public let reversible: Bool?
        public let reverseActions: [EdgeAction]?
        public let preconditions: [String]?
        public let validated: Bool?
    }

    public struct EdgeAction: Codable, Sendable {
        public let type: ActionType
        public let url: String?
        public let target: ElementTarget?
        public let direction: String?
        public let text: String?
        public let key: String?

        public enum ActionType: String, Codable, Sendable {
            case deeplink
            case tap
            case swipe
            case typeText = "type_text"
            case keyPress = "key_press"
        }
    }

    public struct ElementTarget: Codable, Sendable {
        public let accessibilityId: String?
        public let accessibilityLabel: String?
        public let x: Double?
        public let y: Double?
    }

    public struct EdgeParameter: Codable, Sendable {
        public let name: String
        public let type: String
        public let required: Bool
        public let exampleValue: String?
    }

    public struct NavCommand: Codable, Sendable {
        public let id: String
        public let description: String
        public let deeplinkTemplate: String
        public let behavior: String
    }

    // MARK: - State

    private var graph: NavGraph?
    private var graphPath: String?

    public init() {}

    // MARK: - Loading

    /// Load a navigation graph from a JSON file.
    public func load(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(NavGraph.self, from: data)
        graph = decoded
        graphPath = path
    }

    /// Whether a graph is currently loaded.
    public func isLoaded() -> Bool {
        graph != nil
    }

    /// Unload the current graph.
    public func unload() {
        graph = nil
        graphPath = nil
    }

    // MARK: - Queries

    /// Get the full loaded graph.
    public func getGraph() -> NavGraph? {
        graph
    }

    /// Get the path the graph was loaded from.
    public func getGraphPath() -> String? {
        graphPath
    }

    /// Get a specific node by ID.
    public func getNode(_ id: String) -> NavNode? {
        graph?.nodes[id]
    }

    /// Get all nodes.
    public func allNodes() -> [NavNode] {
        guard let graph else { return [] }
        return Array(graph.nodes.values)
    }

    /// Get all edges originating from a specific node (or globally routable).
    public func edges(from nodeId: String) -> [NavEdge] {
        guard let graph else { return [] }
        return graph.edges.filter { $0.from == nodeId || $0.from == "*" }
    }

    /// Get all edges targeting a specific node.
    public func edges(to nodeId: String) -> [NavEdge] {
        guard let graph else { return [] }
        return graph.edges.filter { $0.to == nodeId }
    }

    /// Get navigation commands.
    public func getCommands() -> [NavCommand] {
        graph?.commands ?? []
    }

    // MARK: - Pathfinding

    /// BFS shortest path from one node to another.
    /// Returns the sequence of edges to traverse, or nil if no path exists.
    public func shortestPath(from: String, to target: String) -> [NavEdge]? {
        guard let graph else { return nil }
        guard graph.nodes[target] != nil else { return nil }

        // Check for direct edges first (including globally routable "*" edges)
        let directEdges = graph.edges.filter {
            ($0.from == from || $0.from == "*") && $0.to == target
        }
        if let direct = directEdges.first {
            return [direct]
        }

        // BFS
        var queue: [(nodeId: String, path: [NavEdge])] = [(from, [])]
        var visited: Set<String> = [from]

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()

            let outgoing = graph.edges.filter {
                ($0.from == current || $0.from == "*") && $0.to != nil
            }

            for edge in outgoing {
                guard let nextNode = edge.to, !visited.contains(nextNode) else { continue }

                let newPath = path + [edge]

                if nextNode == target {
                    return newPath
                }

                visited.insert(nextNode)
                queue.append((nextNode, newPath))
            }
        }

        return nil
    }

    // MARK: - Fingerprint Matching

    /// Match an accessibility tree snapshot against graph nodes.
    /// Returns the best matching node ID and a confidence level.
    public func matchFingerprint(
        accessibilityIds: Set<String>,
        staticTexts: [String]
    ) -> (nodeId: String, confidence: String)? {
        guard let graph else { return nil }

        // Layer 1: Match by accessibility ID
        for (nodeId, node) in graph.nodes {
            if let fingerprint = node.fingerprint,
               let rootId = fingerprint.accessibilityId,
               accessibilityIds.contains(rootId) {
                return (nodeId, "high")
            }
        }

        // Layer 2: Match by dominant static text
        for (nodeId, node) in graph.nodes {
            if let fingerprint = node.fingerprint,
               let dominantText = fingerprint.dominantStaticText,
               staticTexts.contains(dominantText) {
                return (nodeId, "medium")
            }
        }

        return nil
    }

    // MARK: - Mutation

    /// Set the fingerprint for a node. Returns false if the node doesn't exist.
    /// When `force` is false, skips nodes that already have a fingerprint.
    @discardableResult
    public func setFingerprint(
        nodeId: String,
        fingerprint: NodeFingerprint,
        force: Bool = false
    ) -> Bool {
        guard var g = graph, let existing = g.nodes[nodeId] else { return false }

        if !force && existing.fingerprint != nil { return false }

        let updated = NavNode(
            id: existing.id,
            name: existing.name,
            isTabRoot: existing.isTabRoot,
            supportedTabs: existing.supportedTabs,
            isCMSDriven: existing.isCMSDriven,
            deeplinkTemplate: existing.deeplinkTemplate,
            subTabs: existing.subTabs,
            fingerprint: fingerprint,
            validated: existing.validated
        )
        g.nodes[nodeId] = updated
        graph = g
        return true
    }

    // MARK: - Persistence

    /// Save the current graph to a JSON file.
    /// Defaults to the path it was loaded from, or a specified path.
    public func save(to path: String? = nil) throws {
        guard let graph else {
            throw ToolError(code: .invalidInput, message: "No graph loaded to save.")
        }

        guard let destination = path ?? graphPath else {
            throw ToolError(code: .invalidInput, message: "No save path specified and no original path available.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(graph)
        try data.write(to: URL(fileURLWithPath: destination))
    }
}
