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
    ///   - maxSizeBytes: Maximum total size of stored artifacts (default 2 GB).
    ///   - ttl: Time-to-live for artifacts in seconds (default 24 hours).
    public init(
        baseDirectory: URL,
        maxSizeBytes: Int = 2 * 1024 * 1024 * 1024,
        ttl: TimeInterval = 86_400
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

        evictToFitCap()

        return ArtifactReference(path: fileURL.path, mimeType: mimeType)
    }

    /// Remove expired artifacts.
    public func evictExpired() {
        let now = Date()
        let expired = entries.filter { now.timeIntervalSince($0.value.createdAt) > ttl }

        for (id, _) in expired {
            removeEntry(id)
        }
    }

    /// Total size of all stored artifacts.
    public func totalSize() -> Int {
        entries.values.reduce(0) { $0 + $1.size }
    }

    /// Scan base directory for subdirectories older than TTL based on filesystem creation dates.
    /// Removes orphaned artifacts from previous server sessions that aren't tracked in memory.
    public func cleanupStaleDirectories() throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-ttl)

        for url in contents {
            // Skip entries tracked by this session
            let dirname = url.lastPathComponent
            if entries[dirname] != nil { continue }

            guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                  let created = values.creationDate,
                  created < cutoff else { continue }

            try? fm.removeItem(at: url)
            logger.debug("Cleaned up stale directory: \(url.lastPathComponent)")
        }
    }

    // MARK: - Private

    /// Remove oldest entries until total size fits within the cap.
    private func evictToFitCap() {
        while totalSize() > maxSizeBytes {
            guard let oldest = entries.values.min(by: { $0.createdAt < $1.createdAt }) else { break }
            removeEntry(oldest.id)
        }
    }

    /// Remove an entry's file, its UUID parent directory, and the in-memory record.
    private func removeEntry(_ id: String) {
        guard let entry = entries[id] else { return }
        let directory = baseDirectory.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: directory)
        entries[id] = nil
        logger.debug("Evicted artifact: \(entry.path)")
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
