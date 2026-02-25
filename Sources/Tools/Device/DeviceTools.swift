//
//  DeviceTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all device tools: list_devices, build_device, build_run_device,
/// test_device, install_app_device, launch_app_device, stop_app_device, device_screenshot.
func registerDeviceTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator,
    progressReporter: ProgressReporter? = nil
) async {
    await registerListDevicesTool(with: registry, session: session, executor: executor)
    await registerBuildDeviceTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator, progressReporter: progressReporter)
    await registerBuildRunDeviceTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator, progressReporter: progressReporter)
    await registerTestDeviceTool(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, validator: validator, progressReporter: progressReporter)
    await registerInstallAppDeviceTool(with: registry, session: session, executor: executor, concurrency: concurrency, validator: validator)
    await registerLaunchAppDeviceTool(with: registry, session: session, executor: executor, concurrency: concurrency, validator: validator)
    await registerStopAppDeviceTool(with: registry, session: session, executor: executor, validator: validator)
    await registerDeviceScreenshotTool(with: registry, session: session, executor: executor, artifacts: artifacts, validator: validator)
}
