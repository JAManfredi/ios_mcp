//
//  BuildTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all build tools: build_sim, build_run_sim, launch_app, stop_app, test_sim, clean_derived_data.
func registerBuildTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    await registerBuildSimTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator)
    await registerBuildRunSimTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator)
    await registerLaunchAppTool(with: registry, session: session, executor: executor, validator: validator)
    await registerStopAppTool(with: registry, session: session, executor: executor, validator: validator)
    await registerTestSimTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator)
    await registerCleanDerivedDataTool(with: registry, session: session)
}
