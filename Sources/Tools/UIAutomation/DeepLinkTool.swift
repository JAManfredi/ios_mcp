//
//  DeepLinkTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerDeepLinkTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator,
    urlOpener: SimulatorURLOpener = SimulatorURLOpener()
) async {
    let manifest = ToolManifest(
        name: "deep_link",
        description: "Open a URL (deep link or universal link) in the iOS simulator. The first time a custom scheme is opened on a simulator, ios-mcp records iOS's approval for the installed app that declares it, so the system \"Open in\" prompt doesn't block the link, then checks that no prompt appeared. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "url": .init(
                    type: "string",
                    description: "The URL to open in the simulator (required)."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
            ],
            required: ["url"]
        ),
        category: .uiAutomation,
        isDestructive: true
    )

    await registry.register(manifest: manifest) { args in
        guard case .string(let url) = args["url"] else {
            return .error(ToolError(
                code: .invalidInput,
                message: "Missing required parameter: url"
            ))
        }

        var udid: String?
        if case .string(let u) = args["udid"] {
            udid = u
        }

        if udid == nil {
            udid = await session.get(.simulatorUDID)
        }

        guard let resolvedUDID = udid else {
            return .error(ToolError(
                code: .invalidInput,
                message: "No simulator UDID provided, and no session default is set. Run list_simulators first."
            ))
        }

        if let error = await validator.validateSimulatorUDID(resolvedUDID) {
            return .error(error)
        }

        switch await urlOpener.open(url, udid: resolvedUDID, executor: executor) {
        case .success(let notes):
            let content = (["Opened URL '\(url)' on simulator \(resolvedUDID)."] + notes).joined(separator: "\n")
            return .success(ToolResult(content: content))
        case .failure(let error):
            return .error(error)
        }
    }
}
