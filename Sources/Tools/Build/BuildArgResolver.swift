//
//  BuildArgResolver.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

/// Resolved build arguments for xcodebuild commands.
struct ResolvedBuildArgs: Sendable {
    let workspaceArg: String?
    let projectArg: String?
    let scheme: String
    let configuration: String
    let udid: String
    let derivedDataPath: String?
    let extraArgs: [String]
    let lockKey: String
}

/// Extracts and resolves workspace/project/scheme/configuration/udid from tool
/// arguments with session fallback. Shared by build_sim, build_run_sim, and test_sim.
/// Validates resolved paths and UDID against actual system state.
func resolveBuildArgs(
    from args: [String: Value],
    session: SessionStore,
    validator: DefaultsValidator
) async -> Result<ResolvedBuildArgs, ToolError> {
    let workspace: String?
    if case .string(let ws) = args["workspace"] {
        workspace = ws
    } else {
        workspace = await session.get(.workspace)
    }

    let project: String?
    if case .string(let proj) = args["project"] {
        project = proj
    } else {
        project = await session.get(.project)
    }

    let scheme: String?
    if case .string(let s) = args["scheme"] {
        scheme = s
    } else {
        scheme = await session.get(.scheme)
    }

    let configuration: String
    if case .string(let c) = args["configuration"] {
        configuration = c
    } else if let sessionConfig = await session.get(.configuration) {
        configuration = sessionConfig
    } else {
        configuration = "Debug"
    }

    let udid: String?
    if case .string(let u) = args["udid"] {
        udid = u
    } else {
        udid = await session.get(.simulatorUDID)
    }

    let derivedDataPath: String?
    if case .string(let ddp) = args["derived_data_path"] {
        derivedDataPath = ddp
    } else {
        derivedDataPath = await session.get(.derivedDataPath)
    }

    var extraArgs: [String] = []
    if case .string(let extra) = args["extra_args"] {
        extraArgs = extra.components(separatedBy: " ").filter { !$0.isEmpty }
    }

    guard let scheme else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No scheme specified, and no session default is set. Run list_schemes first."
        ))
    }

    guard workspace != nil || project != nil else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No workspace or project specified, and no session default is set. Run discover_projects first."
        ))
    }

    guard let udid else {
        return .failure(ToolError(
            code: .invalidInput,
            message: "No simulator UDID specified, and no session default is set. Run list_simulators first."
        ))
    }

    // Validate resolved values against actual system state
    if let workspace, let error = validator.validatePathExists(workspace, label: "Workspace") {
        return .failure(error)
    }
    if let project, workspace == nil, let error = validator.validatePathExists(project, label: "Project") {
        return .failure(error)
    }
    if let error = await validator.validateSimulatorUDID(udid) {
        return .failure(error)
    }

    let lockKey = "build:\(workspace ?? project ?? scheme)"

    return .success(ResolvedBuildArgs(
        workspaceArg: workspace,
        projectArg: project,
        scheme: scheme,
        configuration: configuration,
        udid: udid,
        derivedDataPath: derivedDataPath,
        extraArgs: extraArgs,
        lockKey: lockKey
    ))
}

/// Builds the xcodebuild base argument array from resolved args.
func xcodebuildBaseArgs(
    from resolved: ResolvedBuildArgs,
    resultBundlePath: String
) -> [String] {
    var args: [String] = []

    if let workspace = resolved.workspaceArg {
        args += ["-workspace", workspace]
    } else if let project = resolved.projectArg {
        args += ["-project", project]
    }

    args += ["-scheme", resolved.scheme]
    args += ["-configuration", resolved.configuration]
    args += ["-destination", "platform=iOS Simulator,id=\(resolved.udid)"]

    if let ddp = resolved.derivedDataPath {
        args += ["-derivedDataPath", ddp]
    }

    args += ["-resultBundlePath", resultBundlePath]
    args += resolved.extraArgs

    return args
}
