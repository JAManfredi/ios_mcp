//
//  NavigationTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all navigation graph tools: load_nav_graph, get_nav_graph,
/// navigate_to, where_am_i, tag_screen, save_nav_graph.
func registerNavigationTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    navGraph: NavGraphStore,
    validator: DefaultsValidator
) async {
    await registerLoadNavGraphTool(with: registry, navGraph: navGraph)
    await registerGetNavGraphTool(with: registry, navGraph: navGraph)
    await registerNavigateToTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: validator)
    await registerWhereAmITool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: validator)
    await registerTagScreenTool(with: registry, session: session, executor: executor, navGraph: navGraph, validator: validator)
    await registerSaveNavGraphTool(with: registry, navGraph: navGraph)
}
