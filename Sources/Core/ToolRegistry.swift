//
//  ToolRegistry.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP

/// Central registry mapping tool names to their manifests and handler closures.
public actor ToolRegistry {
    public typealias ToolHandler = @Sendable ([String: Value]) async throws -> ToolResponse

    private var manifests: [String: ToolManifest] = [:]
    private var handlers: [String: ToolHandler] = [:]

    public init() {}

    /// Register a tool with its manifest and handler.
    public func register(
        manifest: ToolManifest,
        handler: @escaping ToolHandler
    ) {
        manifests[manifest.name] = manifest
        handlers[manifest.name] = handler
    }

    /// All registered tool manifests.
    public func listTools() -> [ToolManifest] {
        Array(manifests.values)
    }

    /// Invoke a tool by name with the given arguments.
    public func callTool(
        name: String,
        arguments: [String: Value]
    ) async throws -> ToolResponse {
        guard let handler = handlers[name] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Unknown tool: \(name)"
            ))
        }
        return try await handler(arguments)
    }
}

// MARK: - MCP Conversion

extension ToolManifest {
    /// Convert to MCP SDK `Tool` representation.
    public func mcpTool() -> Tool {
        let annotations = Tool.Annotations(
            readOnlyHint: isReadOnly ? true : nil,
            destructiveHint: isDestructive ? true : nil
        )
        return Tool(
            name: name,
            description: description,
            inputSchema: mcpInputSchema(),
            annotations: annotations
        )
    }

    private func mcpInputSchema() -> Value {
        var props: [String: Value] = [:]
        for (key, prop) in inputSchema.properties {
            var propDict: [String: Value] = [
                "type": .string(prop.type),
                "description": .string(prop.description),
            ]
            if let enumVals = prop.enumValues {
                propDict["enum"] = .array(enumVals.map { .string($0) })
            }
            props[key] = .object(propDict)
        }

        return .object([
            "type": .string(inputSchema.type),
            "properties": .object(props),
            "required": .array(inputSchema.required.map { .string($0) }),
        ])
    }
}
