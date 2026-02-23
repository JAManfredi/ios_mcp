//
//  SessionValidator.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Validates session defaults (UDIDs, paths) against actual system state.
/// Returns nil when valid, ToolError when stale.
public struct DefaultsValidator: Sendable {
    private let executor: any CommandExecuting
    private let fileExists: @Sendable (String) -> Bool

    public init(
        executor: any CommandExecuting,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.executor = executor
        self.fileExists = fileExists
    }

    /// Validates that a simulator UDID exists in `simctl list devices`.
    /// Returns nil if valid or if simctl fails (graceful degradation).
    public func validateSimulatorUDID(_ udid: String) async -> ToolError? {
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "-j"],
                timeout: 15,
                environment: nil
            )

            guard result.succeeded, let data = result.stdout.data(using: .utf8) else {
                return nil
            }

            struct DeviceList: Decodable {
                let devices: [String: [Device]]
            }
            struct Device: Decodable {
                let udid: String
            }

            let decoded = try JSONDecoder().decode(DeviceList.self, from: data)
            let allUDIDs = decoded.devices.values.flatMap { $0 }.map(\.udid)

            if allUDIDs.contains(udid) { return nil }

            return ToolError(
                code: .staleDefault,
                message: "Simulator UDID '\(udid)' not found in available devices. Run list_simulators to pick a valid device, then session_set_defaults to update."
            )
        } catch {
            return nil
        }
    }

    /// Validates that a filesystem path exists.
    /// Returns nil if the path exists, ToolError if missing.
    public func validatePathExists(
        _ path: String,
        label: String
    ) -> ToolError? {
        if fileExists(path) { return nil }

        return ToolError(
            code: .staleDefault,
            message: "\(label) path does not exist: \(path). Run discover_projects to find valid paths, then session_set_defaults to update."
        )
    }
}
