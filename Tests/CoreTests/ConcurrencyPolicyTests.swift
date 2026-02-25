//
//  ConcurrencyPolicyTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core

@Suite("ConcurrencyPolicy")
struct ConcurrencyPolicyTests {
    @Test("Acquire succeeds when unlocked")
    func acquireUnlocked() async {
        let policy = ConcurrencyPolicy()
        let error = await policy.acquire(key: "build", owner: "test")
        #expect(error == nil)
    }

    @Test("Acquire fails when already locked")
    func acquireLocked() async {
        let policy = ConcurrencyPolicy()
        _ = await policy.acquire(key: "build", owner: "first")
        let error = await policy.acquire(key: "build", owner: "second")
        #expect(error != nil)
        #expect(error?.code == .resourceBusy)
    }

    @Test("Release allows re-acquire")
    func releaseAndReacquire() async {
        let policy = ConcurrencyPolicy()
        _ = await policy.acquire(key: "build", owner: "first")
        await policy.release(key: "build")
        let error = await policy.acquire(key: "build", owner: "second")
        #expect(error == nil)
    }

    @Test("withLock acquires, runs operation, and releases")
    func withLockReleasesAfterOperation() async {
        let policy = ConcurrencyPolicy()

        let response = await policy.withLock(key: "sim:ABC", owner: "boot") {
            .success(ToolResult(content: "done"))
        }

        if case .success(let result) = response {
            #expect(result.content == "done")
        } else {
            Issue.record("Expected success response")
        }

        let isLocked = await policy.isLocked(key: "sim:ABC")
        #expect(!isLocked)
    }

    @Test("withLock releases lock when operation returns error")
    func withLockReleasesOnError() async {
        let policy = ConcurrencyPolicy()

        let response = await policy.withLock(key: "build:test", owner: "build_simulator") {
            .error(ToolError(code: .commandFailed, message: "Build failed"))
        }

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }

        let isLocked = await policy.isLocked(key: "build:test")
        #expect(!isLocked, "Lock should be released even when operation returns an error")
    }

    @Test("withLock returns error when resource busy")
    func withLockResourceBusy() async {
        let policy = ConcurrencyPolicy()
        _ = await policy.acquire(key: "sim:ABC", owner: "first")

        let response = await policy.withLock(key: "sim:ABC", owner: "second") {
            .success(ToolResult(content: "should not run"))
        }

        if case .error(let error) = response {
            #expect(error.code == .resourceBusy)
        } else {
            Issue.record("Expected error response")
        }
    }
}
