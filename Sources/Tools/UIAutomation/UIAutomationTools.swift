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
    artifacts: ArtifactStore
) async {
    await registerScreenshotTool(with: registry, session: session, executor: executor, artifacts: artifacts)
    await registerDeepLinkTool(with: registry, session: session, executor: executor)
    await registerSnapshotUITool(with: registry, session: session, executor: executor)
    await registerTapTool(with: registry, session: session, executor: executor)
    await registerSwipeTool(with: registry, session: session, executor: executor)
    await registerTypeTextTool(with: registry, session: session, executor: executor)
    await registerKeyPressTool(with: registry, session: session, executor: executor)
    await registerLongPressTool(with: registry, session: session, executor: executor)
}
