//
//  ListSimulatorsTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerListSimulatorsTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting
) async {
    let manifest = ToolManifest(
        name: "list_simulators",
        description: "List available iOS simulators with their UDID, name, runtime, and state. Filters out unavailable devices by default. Automatically sets session simulator_udid when exactly one booted device is found.",
        inputSchema: JSONSchema(
            properties: [
                "runtime": .init(
                    type: "string",
                    description: "Filter by runtime (substring match, e.g. 'iOS 18')."
                ),
                "state": .init(
                    type: "string",
                    description: "Filter by device state.",
                    enumValues: ["Booted", "Shutdown"]
                ),
                "show_unavailable": .init(
                    type: "boolean",
                    description: "Include unavailable devices. Defaults to false."
                ),
            ]
        ),
        category: .simulator
    )

    await registry.register(manifest: manifest) { args in
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "-j"],
                timeout: 30,
                environment: nil
            )

            guard result.succeeded else {
                return .error(ToolError(
                    code: .commandFailed,
                    message: "simctl list devices failed",
                    details: result.stderr
                ))
            }

            guard let jsonData = result.stdout.data(using: .utf8) else {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to read simctl output as UTF-8"
                ))
            }

            let simulators: [SimulatorInfo]
            do {
                simulators = try parseSimctlDevices(jsonData)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to parse simctl JSON: \(error.localizedDescription)"
                ))
            }

            let showUnavailable: Bool
            if case .bool(let flag) = args["show_unavailable"] {
                showUnavailable = flag
            } else {
                showUnavailable = false
            }

            let runtimeFilter: String?
            if case .string(let rt) = args["runtime"] {
                runtimeFilter = rt
            } else {
                runtimeFilter = nil
            }

            let stateFilter: String?
            if case .string(let st) = args["state"] {
                stateFilter = st
            } else {
                stateFilter = nil
            }

            var filtered = simulators
            if !showUnavailable {
                filtered = filtered.filter(\.isAvailable)
            }
            if let runtimeFilter {
                filtered = filtered.filter { $0.runtime.localizedCaseInsensitiveContains(runtimeFilter) }
            }
            if let stateFilter {
                filtered = filtered.filter { $0.state == stateFilter }
            }

            if filtered.isEmpty {
                return .success(ToolResult(content: "No simulators found matching the given criteria."))
            }

            let grouped = Dictionary(grouping: filtered, by: \.runtime)
            var lines: [String] = ["Found \(filtered.count) simulator(s):\n"]

            for runtime in grouped.keys.sorted() {
                lines.append("[\(runtime)]")
                for sim in grouped[runtime]! {
                    let availability = sim.isAvailable ? "" : " (unavailable)"
                    lines.append("  \(sim.name) — \(sim.state)\(availability)")
                    lines.append("    UDID: \(sim.udid)")
                }
            }

            let booted = filtered.filter { $0.state == "Booted" }
            if booted.count == 1 {
                await session.set(.simulatorUDID, value: booted[0].udid)
                lines.append("\nSession default set: simulator_udid = \(booted[0].udid)")
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to list simulators: \(error.localizedDescription)"
            ))
        }
    }
}

// MARK: - Codable Structs

struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]
}

struct SimctlDevice: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
    let deviceTypeIdentifier: String
}

struct SimulatorInfo: Sendable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
    let runtime: String
}

// MARK: - Parser

func parseSimctlDevices(_ jsonData: Data) throws -> [SimulatorInfo] {
    let decoded = try JSONDecoder().decode(SimctlDeviceList.self, from: jsonData)
    var results: [SimulatorInfo] = []

    for (runtimeIdentifier, devices) in decoded.devices {
        let runtime = runtimeDisplayName(from: runtimeIdentifier)
        for device in devices {
            results.append(SimulatorInfo(
                udid: device.udid,
                name: device.name,
                state: device.state,
                isAvailable: device.isAvailable,
                runtime: runtime
            ))
        }
    }

    return results.sorted { $0.runtime < $1.runtime }
}

/// Converts "com.apple.CoreSimulator.SimRuntime.iOS-18-0" → "iOS 18.0"
func runtimeDisplayName(from identifier: String) -> String {
    let prefix = "com.apple.CoreSimulator.SimRuntime."
    guard identifier.hasPrefix(prefix) else { return identifier }

    let stripped = String(identifier.dropFirst(prefix.count))
    // "iOS-18-0" → split on first "-" to get platform and version parts
    guard let firstDash = stripped.firstIndex(of: "-") else { return stripped }

    let platform = String(stripped[stripped.startIndex..<firstDash])
    let versionPart = String(stripped[stripped.index(after: firstDash)...])
    let version = versionPart.replacingOccurrences(of: "-", with: ".")

    return "\(platform) \(version)"
}
