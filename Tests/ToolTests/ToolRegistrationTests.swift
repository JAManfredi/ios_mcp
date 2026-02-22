//
//  ToolRegistrationTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core
@testable import Tools

@Suite("Tool Registration")
struct ToolRegistrationTests {
    @Test("Registers all tools")
    func registerAll() async {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let tools = await registry.listTools()
        #expect(tools.count == 8)

        let names = Set(tools.map(\.name))
        #expect(names.contains("discover_projects"))
        #expect(names.contains("list_schemes"))
        #expect(names.contains("show_build_settings"))
        #expect(names.contains("list_simulators"))
        #expect(names.contains("boot_simulator"))
        #expect(names.contains("shutdown_simulator"))
        #expect(names.contains("erase_simulator"))
        #expect(names.contains("session_set_defaults"))
    }
}
