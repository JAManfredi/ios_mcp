//
//  ToolResponse.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Structured response from a tool invocation.
public enum ToolResponse: Sendable {
    case success(ToolResult)
    case error(ToolError)
}

// MARK: - ToolResult

public struct ToolResult: Sendable {
    public let content: String
    public let artifacts: [ArtifactReference]

    public init(
        content: String,
        artifacts: [ArtifactReference] = []
    ) {
        self.content = content
        self.artifacts = artifacts
    }
}

// MARK: - ArtifactReference

public struct ArtifactReference: Sendable {
    public let path: String
    public let mimeType: String

    public init(
        path: String,
        mimeType: String
    ) {
        self.path = path
        self.mimeType = mimeType
    }
}

// MARK: - ToolError

public struct ToolError: Sendable, Error {
    public let code: ErrorCode
    public let message: String
    public let details: String?

    public init(
        code: ErrorCode,
        message: String,
        details: String? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
    }
}

// MARK: - ErrorCode

public enum ErrorCode: String, Sendable {
    case resourceBusy = "resource_busy"
    case dependencyMissing = "dependency_missing"
    case staleDefault = "stale_default"
    case commandDenied = "command_denied"
    case commandFailed = "command_failed"
    case timeout
    case invalidInput = "invalid_input"
    case internalError = "internal_error"
}
