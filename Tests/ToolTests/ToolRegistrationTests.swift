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
    @Test("Register all tools does not crash")
    func registerAll() async {
        let registry = ToolRegistry()
        await registerAllTools(with: registry)
        // No tools registered yet — just verifying the function runs.
        let tools = await registry.listTools()
        #expect(tools.isEmpty)
    }
}
