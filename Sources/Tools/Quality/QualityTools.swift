//
//  QualityTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all quality tools: lint, accessibility_audit.
func registerQualityTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    await registerLintTool(with: registry, session: session, executor: executor)
    await registerAccessibilityAuditTool(with: registry, session: session, executor: executor)
}
