//
//  ToolRegistration.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all tool implementations with the given registry.
/// Tool modules will add their registrations here as they're implemented.
public func registerAllTools(with registry: ToolRegistry) async {
    // Phase 1 tools will be registered here as they're implemented.
    // Each tool module (ProjectDiscovery, Simulator, Build, etc.) will
    // provide a registration function called from here.
}
