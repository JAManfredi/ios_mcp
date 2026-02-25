//
//  SimulatorTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all simulator tools.
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
    await registerSimulateLocationTool(with: registry, session: session, executor: executor, validator: validator)
    await registerClearLocationTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSetAppearanceTool(with: registry, session: session, executor: executor, validator: validator)
    await registerOverrideStatusBarTool(with: registry, session: session, executor: executor, validator: validator)
    await registerShowSessionTool(with: registry, session: session)
    await registerClearSessionTool(with: registry, session: session)
    await registerManagePrivacyTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSendPushNotificationTool(with: registry, session: session, executor: executor, validator: validator)
    await registerGetAppContainerTool(with: registry, session: session, executor: executor, validator: validator)
    await registerUninstallAppTool(with: registry, session: session, executor: executor, validator: validator)
}
