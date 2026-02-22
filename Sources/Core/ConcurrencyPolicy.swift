//
//  ConcurrencyPolicy.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Tracks active locks per resource key to prevent conflicting operations.
/// For example, only one build should run at a time, only one simulator boot per UDID.
public actor ConcurrencyPolicy {
    private var locks: [String: LockInfo] = [:]

    public init() {}

    /// Attempt to acquire a lock for the given resource key.
    /// Returns `nil` if the lock was acquired, or a `ToolError` if the resource is busy.
    public func acquire(
        key: String,
        owner: String
    ) -> ToolError? {
        if let existing = locks[key] {
            return ToolError(
                code: .resourceBusy,
                message: "Resource '\(key)' is locked by '\(existing.owner)'"
            )
        }
        locks[key] = LockInfo(owner: owner, acquiredAt: Date())
        return nil
    }

    /// Release a lock for the given resource key.
    public func release(key: String) {
        locks[key] = nil
    }

    /// Check if a resource is currently locked.
    public func isLocked(key: String) -> Bool {
        locks[key] != nil
    }

    /// Acquire a lock, run the operation, and release. Returns the lock error if busy.
    public func withLock(
        key: String,
        owner: String,
        operation: @Sendable () async -> ToolResponse
    ) async -> ToolResponse {
        if let lockError = acquire(key: key, owner: owner) {
            return .error(lockError)
        }
        let response = await operation()
        release(key: key)
        return response
    }
}

// MARK: - LockInfo

struct LockInfo: Sendable {
    let owner: String
    let acquiredAt: Date
}
