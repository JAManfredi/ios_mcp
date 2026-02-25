//
//  SwiftPackageTools.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core

/// Registers all Swift Package tools: swift_package_resolve, swift_package_update,
/// swift_package_init, swift_package_clean, swift_package_show_deps, swift_package_dump.
func registerSwiftPackageTools(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    await registerSwiftPackageResolveTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSwiftPackageUpdateTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSwiftPackageInitTool(with: registry, executor: executor, validator: validator)
    await registerSwiftPackageCleanTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSwiftPackageShowDepsTool(with: registry, session: session, executor: executor, validator: validator)
    await registerSwiftPackageDumpTool(with: registry, session: session, executor: executor, validator: validator)
}
