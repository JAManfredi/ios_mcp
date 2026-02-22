//
//  SessionStore.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Session-scoped state holding current defaults like active simulator,
/// workspace path, scheme, and bundle ID.
public actor SessionStore {
    private var defaults: [Key: String] = [:]

    public init() {}

    public enum Key: String, Sendable, CaseIterable {
        case simulatorUDID = "simulator_udid"
        case workspace
        case project
        case scheme
        case bundleID = "bundle_id"
        case configuration
        case derivedDataPath = "derived_data_path"
    }

    /// Get a session default.
    public func get(_ key: Key) -> String? {
        defaults[key]
    }

    /// Set a session default.
    public func set(_ key: Key, value: String) {
        defaults[key] = value
    }

    /// Remove a session default.
    public func remove(_ key: Key) {
        defaults[key] = nil
    }

    /// All currently set defaults.
    public func allDefaults() -> [Key: String] {
        defaults
    }

    /// Reset all session state.
    public func reset() {
        defaults.removeAll()
    }
}
