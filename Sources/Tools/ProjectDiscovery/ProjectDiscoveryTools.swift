//
//  ProjectDiscoveryTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all project discovery tools: discover_projects, list_schemes, show_build_settings.
func registerProjectDiscoveryTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    await registerDiscoverProjectsTool(with: registry, session: session)
    await registerListSchemesTool(with: registry, session: session, executor: executor)
    await registerShowBuildSettingsTool(with: registry, session: session, executor: executor)
}
