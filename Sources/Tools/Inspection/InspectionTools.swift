//
//  InspectionTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all inspection tools: read_user_defaults, write_user_default.
func registerInspectionTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    await registerReadUserDefaultsTool(with: registry, session: session, executor: executor, validator: validator)
    await registerWriteUserDefaultTool(with: registry, session: session, executor: executor, validator: validator)
}
