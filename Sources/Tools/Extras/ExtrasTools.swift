//
//  ExtrasTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all extras tools: open_simulator.
func registerExtrasTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    await registerOpenSimulatorTool(with: registry, session: session, executor: executor, validator: validator)
}
