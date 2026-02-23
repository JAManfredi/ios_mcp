//
//  UIAutomationTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all UI automation tools: screenshot, deep_link,
/// snapshot_ui, tap, swipe, type_text, key_press, long_press.
func registerUIAutomationTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    artifacts: ArtifactStore,
    validator: DefaultsValidator
) async {
    await registerScreenshotTool(with: registry, session: session, executor: executor, artifacts: artifacts, validator: validator)
    await registerDeepLinkTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSnapshotUITool(with: registry, session: session, executor: executor, validator: validator)
    await registerTapTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSwipeTool(with: registry, session: session, executor: executor, validator: validator)
    await registerTypeTextTool(with: registry, session: session, executor: executor, validator: validator)
    await registerKeyPressTool(with: registry, session: session, executor: executor, validator: validator)
    await registerLongPressTool(with: registry, session: session, executor: executor, validator: validator)
}
