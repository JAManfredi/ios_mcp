//
//  ToolManifest.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Metadata describing an MCP tool's name, schema, and behavior flags.
public struct ToolManifest: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema
    public let category: ToolCategory
    public let isDestructive: Bool
    public let isReadOnly: Bool

    public init(
        name: String,
        description: String,
        inputSchema: JSONSchema,
        category: ToolCategory,
        isDestructive: Bool = false,
        isReadOnly: Bool = false
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.category = category
        self.isDestructive = isDestructive
        self.isReadOnly = isReadOnly
    }
}

// MARK: - ToolCategory

public enum ToolCategory: String, Sendable, CaseIterable {
    case projectDiscovery = "project_discovery"
    case simulator
    case build
    case logging
    case uiAutomation = "ui_automation"
    case debugging
    case inspection
    case quality
    case extras
    case swiftPackage = "swift_package"
    case device
}

// MARK: - JSONSchema

/// Lightweight JSON Schema representation for tool input parameters.
public struct JSONSchema: Sendable {
    public let type: String
    public let properties: [String: Property]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: Property] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public struct Property: Sendable {
        public let type: String
        public let description: String
        public let enumValues: [String]?

        public init(
            type: String,
            description: String,
            enumValues: [String]? = nil
        ) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
        }
    }
}
