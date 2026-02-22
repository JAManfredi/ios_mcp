//
//  SessionStoreTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core

@Suite("SessionStore")
struct SessionStoreTests {
    @Test("Set and get a default")
    func setAndGet() async {
        let store = SessionStore()
        await store.set(.simulatorUDID, value: "ABC-123")
        let value = await store.get(.simulatorUDID)
        #expect(value == "ABC-123")
    }

    @Test("Remove clears value")
    func remove() async {
        let store = SessionStore()
        await store.set(.workspace, value: "/tmp")
        await store.remove(.workspace)
        let value = await store.get(.workspace)
        #expect(value == nil)
    }

    @Test("Reset clears all")
    func reset() async {
        let store = SessionStore()
        await store.set(.scheme, value: "MyApp")
        await store.set(.bundleID, value: "com.example")
        await store.reset()
        let all = await store.allDefaults()
        #expect(all.isEmpty)
    }
}
