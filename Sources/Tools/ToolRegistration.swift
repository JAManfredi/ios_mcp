//
//  ToolRegistration.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all tool implementations with the given registry.
/// Tool modules will add their registrations here as they're implemented.
public func registerAllTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    await registerProjectDiscoveryTools(with: registry, session: session, executor: executor)
}
