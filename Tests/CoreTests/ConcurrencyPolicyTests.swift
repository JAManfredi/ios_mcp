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
}
