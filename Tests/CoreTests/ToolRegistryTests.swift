//
//  ToolRegistryTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test("Register and list tools")
    func registerAndList() async {
        let registry = ToolRegistry()
        let manifest = ToolManifest(
            name: "test_tool",
            description: "A test tool",
            inputSchema: JSONSchema(),
            category: .extras
        )
        await registry.register(manifest: manifest) { _ in
            .success(ToolResult(content: "ok"))
        }
        let tools = await registry.listTools()
        #expect(tools.count == 1)
        #expect(tools.first?.name == "test_tool")
    }

    @Test("Call unknown tool returns error")
    func callUnknown() async throws {
        let registry = ToolRegistry()
        let response = try await registry.callTool(name: "nonexistent", arguments: [:])
        if case .error(let error) = response {
            #expect(error.code == .invalidInput)
        } else {
            Issue.record("Expected error response")
        }
    }
}
