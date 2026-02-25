//
//  SessionSetDefaultsTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerSessionSetDefaultsTool(
    with registry: ToolRegistry,
    session: SessionStore,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "session_set_defaults",
        description: "Manually set session defaults for simulator UDID, workspace, project, scheme, bundle ID, configuration, or derived data path. At least one parameter is required. These defaults are used as fallbacks by other tools.",
        inputSchema: JSONSchema(
            properties: [
                "simulator_udid": .init(
                    type: "string",
                    description: "Simulator UDID to use as default."
                ),
                "workspace": .init(
                    type: "string",
                    description: "Path to .xcworkspace."
                ),
                "project": .init(
                    type: "string",
                    description: "Path to .xcodeproj."
                ),
                "scheme": .init(
                    type: "string",
                    description: "Xcode scheme name."
                ),
                "bundle_id": .init(
                    type: "string",
                    description: "App bundle identifier."
                ),
                "configuration": .init(
                    type: "string",
                    description: "Build configuration (e.g. Debug, Release)."
                ),
                "derived_data_path": .init(
                    type: "string",
                    description: "Custom derived data path."
                ),
                "device_udid": .init(
                    type: "string",
                    description: "Physical device UDID to use as default."
                ),
            ]
        ),
        category: .simulator
    )

    await registry.register(manifest: manifest) { args in
        let keyMap: [(argName: String, key: SessionStore.Key)] = [
            ("simulator_udid", .simulatorUDID),
            ("workspace", .workspace),
            ("project", .project),
            ("scheme", .scheme),
            ("bundle_id", .bundleID),
            ("configuration", .configuration),
            ("derived_data_path", .derivedDataPath),
            ("device_udid", .deviceUDID),
        ]

        // Validate UDID before setting
        if case .string(let udidValue) = args["simulator_udid"] {
            if let error = await validator.validateSimulatorUDID(udidValue) {
                return .error(error)
            }
        }

        // Validate workspace path before setting
        if case .string(let wsValue) = args["workspace"] {
            if let error = validator.validatePathExists(wsValue, label: "Workspace") {
                return .error(error)
            }
        }

        // Validate project path before setting
        if case .string(let projValue) = args["project"] {
            if let error = validator.validatePathExists(projValue, label: "Project") {
                return .error(error)
            }
        }

        var setKeys: [String] = []

        for (argName, key) in keyMap {
            if case .string(let value) = args[argName] {
                await session.set(key, value: value)
                setKeys.append("\(key.rawValue) = \(value)")
            }
        }

        guard !setKeys.isEmpty else {
            return .error(ToolError(
                code: .invalidInput,
                message: "At least one session default must be provided."
            ))
        }

        var lines = ["Session defaults updated:"]
        for entry in setKeys {
            lines.append("  \(entry)")
        }

        return .success(ToolResult(content: lines.joined(separator: "\n")))
    }
}
