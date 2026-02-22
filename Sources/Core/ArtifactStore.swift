//
//  ArtifactStore.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Logging

/// File-backed artifact manager with TTL and size cap.
/// Stores screenshots, logs, and other transient outputs.
public actor ArtifactStore {
    private let baseDirectory: URL
    private let maxSizeBytes: Int
    private let ttl: TimeInterval
    private let logger = Logger(label: "ios-mcp.artifact-store")

    private var entries: [String: ArtifactEntry] = [:]

    /// - Parameters:
    ///   - baseDirectory: Root directory for artifact storage.
    ///   - maxSizeBytes: Maximum total size of stored artifacts (default 100 MB).
    ///   - ttl: Time-to-live for artifacts in seconds (default 1 hour).
    public init(
        baseDirectory: URL,
        maxSizeBytes: Int = 100 * 1024 * 1024,
        ttl: TimeInterval = 3600
    ) {
        self.baseDirectory = baseDirectory
        self.maxSizeBytes = maxSizeBytes
        self.ttl = ttl
    }

    /// Store data as an artifact and return a reference.
    public func store(
        data: Data,
        filename: String,
        mimeType: String
    ) throws -> ArtifactReference {
        let id = UUID().uuidString
        let directory = baseDirectory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        let entry = ArtifactEntry(
            id: id,
            path: fileURL.path,
            mimeType: mimeType,
            size: data.count,
            createdAt: Date()
        )
        entries[id] = entry

        logger.debug("Stored artifact: \(filename) (\(data.count) bytes)")

        return ArtifactReference(path: fileURL.path, mimeType: mimeType)
    }

    /// Remove expired artifacts.
    public func evictExpired() {
        let now = Date()
        let expired = entries.filter { now.timeIntervalSince($0.value.createdAt) > ttl }

        for (id, entry) in expired {
            try? FileManager.default.removeItem(atPath: entry.path)
            entries[id] = nil
            logger.debug("Evicted artifact: \(entry.path)")
        }
    }

    /// Total size of all stored artifacts.
    public func totalSize() -> Int {
        entries.values.reduce(0) { $0 + $1.size }
    }
}

// MARK: - ArtifactEntry

struct ArtifactEntry: Sendable {
    let id: String
    let path: String
    let mimeType: String
    let size: Int
    let createdAt: Date
}
