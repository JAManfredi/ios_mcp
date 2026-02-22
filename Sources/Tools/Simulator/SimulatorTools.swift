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
    concurrency: ConcurrencyPolicy
) async {
    await registerListSimulatorsTool(with: registry, session: session, executor: executor)
    await registerBootSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency)
    await registerShutdownSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency)
    await registerEraseSimulatorTool(with: registry, session: session, executor: executor, concurrency: concurrency)
    await registerSessionSetDefaultsTool(with: registry, session: session)
}
