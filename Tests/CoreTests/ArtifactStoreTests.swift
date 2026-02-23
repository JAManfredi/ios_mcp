//
//  ArtifactStoreTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("ArtifactStore")
struct ArtifactStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("artifact-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Stores artifact and tracks size")
    func storeBasic() async throws {
        let dir = try makeTempDir()
        let store = ArtifactStore(baseDirectory: dir)

        let data = Data(repeating: 0xAB, count: 128)
        let ref = try await store.store(data: data, filename: "test.bin", mimeType: "application/octet-stream")

        #expect(FileManager.default.fileExists(atPath: ref.path))
        #expect(await store.totalSize() == 128)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Evicts expired artifacts")
    func evictsExpired() async throws {
        let dir = try makeTempDir()
        let store = ArtifactStore(baseDirectory: dir, ttl: 0)

        let data = Data(repeating: 0x01, count: 64)
        let ref = try await store.store(data: data, filename: "ephemeral.bin", mimeType: "application/octet-stream")

        await store.evictExpired()

        #expect(!FileManager.default.fileExists(atPath: ref.path))
        #expect(await store.totalSize() == 0)

        // Verify parent directory is also removed
        let parentDir = URL(fileURLWithPath: ref.path).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: parentDir.path))

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Enforces size cap by evicting oldest entries")
    func enforcesSizeCap() async throws {
        let dir = try makeTempDir()
        let store = ArtifactStore(baseDirectory: dir, maxSizeBytes: 10)

        let first = try await store.store(data: Data(repeating: 0x01, count: 6), filename: "first.bin", mimeType: "application/octet-stream")
        let second = try await store.store(data: Data(repeating: 0x02, count: 6), filename: "second.bin", mimeType: "application/octet-stream")

        // First should be evicted to fit under 10-byte cap
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(await store.totalSize() == 6)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Preserves fresh artifacts during eviction")
    func preservesFreshArtifacts() async throws {
        let dir = try makeTempDir()
        let store = ArtifactStore(baseDirectory: dir)

        let data = Data(repeating: 0xFF, count: 32)
        let ref = try await store.store(data: data, filename: "fresh.bin", mimeType: "application/octet-stream")

        await store.evictExpired()

        #expect(FileManager.default.fileExists(atPath: ref.path))
        #expect(await store.totalSize() == 32)

        try? FileManager.default.removeItem(at: dir)
    }
}
