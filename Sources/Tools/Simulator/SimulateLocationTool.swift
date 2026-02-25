//
//  SimulateLocationTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerSimulateLocationTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "simulate_location",
        description: "Set a simulated GPS location on an iOS simulator. Useful for testing location-based features without physically moving. Use clear_location to revert. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "latitude": .init(
                    type: "number",
                    description: "Latitude coordinate (e.g. 37.7749)."
                ),
                "longitude": .init(
                    type: "number",
                    description: "Longitude coordinate (e.g. -122.4194)."
                ),
            ],
            required: ["latitude", "longitude"]
        ),
        category: .simulator
    )

    await registry.register(manifest: manifest) { args in
        do {
            let udid: String?
            if case .string(let u) = args["udid"] {
                udid = u
            } else {
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

            let latitude: Double
            switch args["latitude"] {
            case .double(let v): latitude = v
            case .int(let v): latitude = Double(v)
            default:
                return .error(ToolError(
                    code: .invalidInput,
                    message: "latitude is required and must be a number."
                ))
            }

            let longitude: Double
            switch args["longitude"] {
            case .double(let v): longitude = v
            case .int(let v): longitude = Double(v)
            default:
                return .error(ToolError(
                    code: .invalidInput,
                    message: "longitude is required and must be a number."
                ))
            }

            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "location", resolvedUDID, "set", "\(latitude),\(longitude)"],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl location set failed",
                    details: result.stderr
                ))
            }

            return .success(ToolResult(
                content: "Location set to \(latitude), \(longitude) on simulator \(resolvedUDID)."
            ))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to simulate location: \(error.localizedDescription)"
            ))
        }
    }
}
