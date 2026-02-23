//
//  SimulatorTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all simulator tools: list_simulators, boot_simulator, shutdown_simulator, erase_simulator, session_set_defaults.
func registerSimulatorTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    await registerListSimulatorsTool(with: registry, session: session, executor: executor)
    await registerBootSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency, validator: validator)
    await registerShutdownSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency, validator: validator)
    await registerEraseSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency, validator: validator)
    await registerSessionSetDefaultsTool(with: registry, session: session, validator: validator)
}
