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
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    logCapture: any LogCapturing
) async {
    await registerProjectDiscoveryTools(with: registry, session: session, executor: executor)
    await registerSimulatorTools(with: registry, session: session, executor: executor, concurrency: concurrency)
    await registerBuildTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts)
    await registerLoggingTools(with: registry, session: session, logCapture: logCapture, concurrency: concurrency)
}
