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
    @Test("Registers all project discovery tools")
    func registerAll() async {
        let registry = ToolRegistry()
        let session = SessionStore()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor)

        let tools = await registry.listTools()
        #expect(tools.count == 3)

        let names = Set(tools.map(\.name))
        #expect(names.contains("discover_projects"))
        #expect(names.contains("list_schemes"))
        #expect(names.contains("show_build_settings"))
    }
}
