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
        public let references: [NavReference]?
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
        /// Label the `accessibilityId` element must have. Use it when screens
        /// share a component, such as a title whose ID is the same on every
        /// tab but whose text differs.
        public let accessibilityLabel: String?
        public let hierarchyHash: String?
        public let dominantStaticText: String?

        public init(
            accessibilityId: String? = nil,
            accessibilityLabel: String? = nil,
            hierarchyHash: String? = nil,
            dominantStaticText: String? = nil
        ) {
            self.accessibilityId = accessibilityId
            self.accessibilityLabel = accessibilityLabel
            self.hierarchyHash = hierarchyHash
            self.dominantStaticText = dominantStaticText
        }
    }

    public struct NavEdge: Codable, Sendable {
        /// Stable identifier for selecting this edge explicitly (e.g. a deeplink case name).
        public let id: String?
        public let from: String
        public let to: String?
        public let actions: [EdgeAction]
        public let parameters: [EdgeParameter]?
        public let reversible: Bool?
        public let reverseActions: [EdgeAction]?
        public let preconditions: [String]?
        public let validated: Bool?
        /// How the destination is presented (e.g. push, sheet, tab_switch, in_tab). Informational.
        public let navMode: String?

        /// Human-readable handle: the edge ID, else its first deeplink URL, else `from → to`.
        public var label: String {
            if let id, !id.isEmpty { return id }
            if let url = actions.first(where: { $0.type == .deeplink })?.url { return url }
            return "\(from) → \(to ?? "(action only)")"
        }

        /// Template placeholders (`{name}`) referenced by this edge's deeplink and text actions.
        public var placeholders: Set<String> {
            var names = Set<String>()
            for action in actions {
                for template in [action.url, action.text].compactMap({ $0 }) {
                    names.formUnion(NavGraphStore.placeholders(in: template))
                }
            }
            return names
        }

        /// Whether `selector` names this edge by ID or by exact deeplink URL template.
        public func matches(selector: String) -> Bool {
            if id == selector { return true }
            return actions.contains { $0.type == .deeplink && $0.url == selector }
        }
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

    public struct NavReference: Codable, Sendable {
        public let file: String
        public let description: String
        public let usedByNodes: [String]?
    }

    // MARK: - State

    private var graph: NavGraph?
    private var graphPath: String?
    /// The file's original JSON, kept so `save` writes back fields this type
    /// doesn't model (generator metadata, custom keys) instead of dropping them.
    private var rawGraph: [String: Any]?
    /// What each screen tagged this session showed, keyed by node ID. Lets
    /// tag_screen tell shared UI (seen on several screens) from screen-specific
    /// elements. Session-only: cleared when a graph is loaded or unloaded.
    private var observedScreens: [String: ObservedScreen] = [:]

    private struct ObservedScreen {
        let accessibilityIds: Set<String>
        let staticTexts: Set<String>
    }

    public init() {}

    // MARK: - Loading

    /// Load a navigation graph from a JSON file.
    public func load(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(NavGraph.self, from: data)
        graph = decoded
        graphPath = path
        rawGraph = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        observedScreens = [:]
    }

    /// Whether a graph is currently loaded.
    public func isLoaded() -> Bool {
        graph != nil
    }

    /// Unload the current graph.
    public func unload() {
        graph = nil
        graphPath = nil
        rawGraph = nil
        observedScreens = [:]
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

    /// Edges that lead directly from `from` (or from anywhere) to `target`, in file order.
    public func directEdges(from: String, to target: String) -> [NavEdge] {
        guard let graph else { return [] }
        return graph.edges.filter { ($0.from == from || $0.from == "*") && $0.to == target }
    }

    /// BFS shortest path from one node to another.
    /// Returns the sequence of edges to traverse, or nil if no path exists.
    ///
    /// When several edges lead to the same node, the hop uses the edge that best
    /// fits `providedParameters` (see `preferredEdge`), so callers reach
    /// `search/{searchTerm}` by supplying `searchTerm` rather than always getting
    /// the first edge in the file.
    public func shortestPath(
        from: String,
        to target: String,
        providedParameters: Set<String> = []
    ) -> [NavEdge]? {
        guard let graph else { return nil }
        guard graph.nodes[target] != nil else { return nil }

        let direct = directEdges(from: from, to: target)
        if let best = Self.preferredEdge(among: direct, providedParameters: providedParameters) {
            return [best]
        }

        // BFS over node IDs; each hop picks the preferred edge into the next node.
        var queue: [(nodeId: String, path: [NavEdge])] = [(from, [])]
        var head = 0
        var visited: Set<String> = [from]

        while head < queue.count {
            let (current, path) = queue[head]
            head += 1

            var nextNodes: [String] = []
            for edge in graph.edges where edge.from == current || edge.from == "*" {
                guard let next = edge.to, !visited.contains(next), !nextNodes.contains(next) else { continue }
                nextNodes.append(next)
            }

            for next in nextNodes {
                let candidates = directEdges(from: current, to: next)
                guard let edge = Self.preferredEdge(among: candidates, providedParameters: providedParameters) else { continue }
                let newPath = path + [edge]
                if next == target { return newPath }
                visited.insert(next)
                queue.append((next, newPath))
            }
        }

        return nil
    }

    /// Choose among parallel edges to the same node.
    ///
    /// Prefers edges whose placeholders are all supplied, then the one that
    /// uses the most supplied parameters (the most specific route). Among edges
    /// that can't be fully resolved, prefers the fewest missing placeholders.
    /// Ties keep file order.
    public static func preferredEdge(
        among edges: [NavEdge],
        providedParameters: Set<String>
    ) -> NavEdge? {
        guard !edges.isEmpty else { return nil }
        func score(_ edge: NavEdge) -> (missing: Int, used: Int) {
            let needed = edge.placeholders
            return (needed.subtracting(providedParameters).count, needed.intersection(providedParameters).count)
        }
        var best = edges[0]
        var bestScore = score(best)
        for edge in edges.dropFirst() {
            let s = score(edge)
            if s.missing < bestScore.missing || (s.missing == bestScore.missing && s.used > bestScore.used) {
                best = edge
                bestScore = s
            }
        }
        return best
    }

    /// Names of `{placeholder}` tokens in a template string.
    public static func placeholders(in template: String) -> Set<String> {
        var names = Set<String>()
        var remainder = template[...]
        while let open = remainder.firstIndex(of: "{") {
            let afterOpen = remainder.index(after: open)
            guard let close = remainder[afterOpen...].firstIndex(of: "}") else { break }
            let name = remainder[afterOpen..<close]
            if !name.isEmpty { names.insert(String(name)) }
            remainder = remainder[remainder.index(after: close)...]
        }
        return names
    }

    // MARK: - Fingerprint Matching

    public struct FingerprintMatch: Sendable, Equatable {
        public let nodeId: String
        /// "high" when every fingerprint field matches and one is an
        /// accessibility ID; "medium" when only static text supports the match.
        public let confidence: String
    }

    /// Every node whose fingerprint matches the snapshot, strongest first.
    ///
    /// A fingerprint's accessibility ID must be on screen, and when the
    /// fingerprint has an `accessibilityLabel`, an element with that ID must
    /// carry that label (`labelsByAccessibilityId`). If its static text is on
    /// screen too (or it has none), the match is high confidence; if the text
    /// is missing, medium. A text-only fingerprint matches at medium.
    /// Within a level, node IDs are sorted so results are stable. More than
    /// one match at the top level means the fingerprints don't distinguish
    /// the screens (often because they captured shared chrome).
    public func fingerprintMatches(
        accessibilityIds: Set<String>,
        staticTexts: [String],
        labelsByAccessibilityId: [String: Set<String>] = [:]
    ) -> [FingerprintMatch] {
        guard let graph else { return [] }
        let texts = Set(staticTexts)
        var high: [String] = []
        var medium: [String] = []

        for (nodeId, node) in graph.nodes {
            guard let fingerprint = node.fingerprint else { continue }
            let textMatches = fingerprint.dominantStaticText.map { texts.contains($0) }
            if let id = fingerprint.accessibilityId {
                guard accessibilityIds.contains(id) else { continue }
                if let label = fingerprint.accessibilityLabel,
                   labelsByAccessibilityId[id]?.contains(label) != true { continue }
                if textMatches == false { medium.append(nodeId) } else { high.append(nodeId) }
            } else if textMatches == true {
                medium.append(nodeId)
            }
        }

        return high.sorted().map { FingerprintMatch(nodeId: $0, confidence: "high") }
            + medium.sorted().map { FingerprintMatch(nodeId: $0, confidence: "medium") }
    }

    /// The single best match, or nil when nothing matches or the top
    /// confidence level is ambiguous (several nodes match equally well).
    public func matchFingerprint(
        accessibilityIds: Set<String>,
        staticTexts: [String],
        labelsByAccessibilityId: [String: Set<String>] = [:]
    ) -> (nodeId: String, confidence: String)? {
        let matches = fingerprintMatches(
            accessibilityIds: accessibilityIds,
            staticTexts: staticTexts,
            labelsByAccessibilityId: labelsByAccessibilityId
        )
        guard let first = matches.first else { return nil }
        let tied = matches.filter { $0.confidence == first.confidence }
        guard tied.count == 1 else { return nil }
        return (first.nodeId, first.confidence)
    }

    /// Accessibility IDs and static texts used by fingerprints on nodes other than `nodeId`.
    public func fingerprintsClaimed(
        excluding nodeId: String
    ) -> (accessibilityIds: Set<String>, staticTexts: Set<String>) {
        guard let graph else { return ([], []) }
        var ids = Set<String>()
        var texts = Set<String>()
        for (id, node) in graph.nodes where id != nodeId {
            if let fpId = node.fingerprint?.accessibilityId { ids.insert(fpId) }
            if let text = node.fingerprint?.dominantStaticText { texts.insert(text) }
        }
        return (ids, texts)
    }

    /// Record what a tagged screen showed, so later tags can avoid elements it shares.
    public func recordObservedScreen(
        nodeId: String,
        accessibilityIds: Set<String>,
        staticTexts: Set<String>
    ) {
        observedScreens[nodeId] = ObservedScreen(accessibilityIds: accessibilityIds, staticTexts: staticTexts)
    }

    /// Accessibility IDs and static texts seen this session on screens tagged
    /// as nodes other than `nodeId`.
    public func elementsObservedOnOtherScreens(
        excluding nodeId: String
    ) -> (accessibilityIds: Set<String>, staticTexts: Set<String>) {
        var ids = Set<String>()
        var texts = Set<String>()
        for (id, screen) in observedScreens where id != nodeId {
            ids.formUnion(screen.accessibilityIds)
            texts.formUnion(screen.staticTexts)
        }
        return (ids, texts)
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

        if var raw = rawGraph,
           var rawNodes = raw["nodes"] as? [String: Any],
           var rawNode = rawNodes[nodeId] as? [String: Any],
           let encoded = try? JSONEncoder().encode(fingerprint),
           let fingerprintObject = try? JSONSerialization.jsonObject(with: encoded) {
            rawNode["fingerprint"] = fingerprintObject
            rawNodes[nodeId] = rawNode
            raw["nodes"] = rawNodes
            rawGraph = raw
        }
        return true
    }

    // MARK: - Persistence

    /// Save the current graph to a JSON file.
    /// Defaults to the path it was loaded from, or a specified path.
    /// Writes the original JSON with fingerprint changes applied, so fields
    /// this type doesn't model survive a load → tag → save round trip.
    public func save(to path: String? = nil) throws {
        guard let graph else {
            throw ToolError(code: .invalidInput, message: "No graph loaded to save.")
        }

        guard let destination = path ?? graphPath else {
            throw ToolError(code: .invalidInput, message: "No save path specified and no original path available.")
        }

        let data: Data
        if let rawGraph {
            data = try JSONSerialization.data(
                withJSONObject: rawGraph,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(graph)
        }
        try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
    }
}
