//
//  Logging.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Logging

/// Configures swift-log for the ios-mcp process.
/// MCP servers must not write to stdout (reserved for JSON-RPC),
/// so all logging goes to stderr.
public enum LoggingConfiguration {
    public static func bootstrap(level: Logger.Level = .info) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
        }
    }
}
