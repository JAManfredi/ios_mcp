//
//  ToolRegistryTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import MCP
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

    @Test("Destructive tool mcpTool() includes destructiveHint annotation")
    func destructiveAnnotation() {
        let manifest = ToolManifest(
            name: "dangerous_tool",
            description: "Destroys things",
            inputSchema: JSONSchema(),
            category: .extras,
            isDestructive: true
        )
        let tool = manifest.mcpTool()
        #expect(tool.annotations.destructiveHint == true)
        #expect(tool.annotations.readOnlyHint == nil)
    }

    @Test("Read-only tool mcpTool() includes readOnlyHint annotation")
    func readOnlyAnnotation() {
        let manifest = ToolManifest(
            name: "safe_tool",
            description: "Only reads",
            inputSchema: JSONSchema(),
            category: .extras,
            isReadOnly: true
        )
        let tool = manifest.mcpTool()
        #expect(tool.annotations.readOnlyHint == true)
        #expect(tool.annotations.destructiveHint == nil)
    }

    @Test("Default tool has no annotation hints set")
    func defaultAnnotations() {
        let manifest = ToolManifest(
            name: "default_tool",
            description: "Normal tool",
            inputSchema: JSONSchema(),
            category: .extras
        )
        let tool = manifest.mcpTool()
        #expect(tool.annotations.readOnlyHint == nil)
        #expect(tool.annotations.destructiveHint == nil)
    }
}
