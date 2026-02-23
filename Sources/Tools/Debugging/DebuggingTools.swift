//
//  DebuggingTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all debugging tools.
func registerDebuggingTools(
    with registry: ToolRegistry,
    session: SessionStore,
    debugSession: any DebugSessionManaging,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    await registerDebugAttachTool(with: registry, session: session, debugSession: debugSession, concurrency: concurrency, validator: validator)
    await registerDebugDetachTool(with: registry, debugSession: debugSession, concurrency: concurrency)
    await registerDebugBreakpointAddTool(with: registry, debugSession: debugSession)
    await registerDebugBreakpointRemoveTool(with: registry, debugSession: debugSession)
    await registerDebugContinueTool(with: registry, debugSession: debugSession)
    await registerDebugStackTool(with: registry, debugSession: debugSession)
    await registerDebugVariablesTool(with: registry, debugSession: debugSession)
    await registerDebugLLDBCommandTool(with: registry, debugSession: debugSession)
}
