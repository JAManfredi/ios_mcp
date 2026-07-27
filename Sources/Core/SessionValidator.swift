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
    private let pathPolicy: PathPolicy?

    public init(
        executor: any CommandExecuting,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        pathPolicy: PathPolicy? = nil
    ) {
        self.executor = executor
        self.fileExists = fileExists
        self.pathPolicy = pathPolicy
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
                let name: String
                let state: String
                let isAvailable: Bool
            }

            let decoded = try JSONDecoder().decode(DeviceList.self, from: data)
            let allDevices = decoded.devices.values.flatMap { $0 }

            if allDevices.contains(where: { $0.udid == udid }) { return nil }

            let candidates = allDevices
                .filter(\.isAvailable)
                .prefix(5)
                .map { "  \($0.udid) — \($0.name) (\($0.state))" }
                .joined(separator: "\n")
            let details: String? = candidates.isEmpty ? nil : "Available devices:\n\(candidates)"

            return ToolError(
                code: .staleDefault,
                message: "Simulator UDID '\(udid)' not found in available devices. Run list_simulators to pick a valid device, then session_set_defaults to update.",
                details: details
            )
        } catch {
            return nil
        }
    }

    /// Validates that a device UDID exists in `devicectl list devices`.
    /// Returns nil if valid or if devicectl fails (graceful degradation).
    public func validateDeviceUDID(_ udid: String) async -> ToolError? {
        if case .failure(let error) = await canonicalDeviceUDID(udid) { return error }
        return nil
    }

    /// Validates a device UDID and returns the identifier `xcodebuild` accepts.
    ///
    /// Callers may hold either identifier — an explicitly passed CoreDevice
    /// UUID, or a hardware UDID from a newer `list_devices`. Both name the same
    /// device, but only the hardware UDID resolves as a `-destination`.
    /// Validating without canonicalizing lets a CoreDevice UUID pass the check
    /// and then fail inside xcodebuild with "Unable to find a device", which
    /// points at the hardware rather than at the identifier.
    ///
    /// Falls back to the caller's value when devicectl can't be queried, so an
    /// unavailable tool degrades to today's behaviour rather than blocking.
    public func canonicalDeviceUDID(_ udid: String) async -> Result<String, ToolError> {
        guard let devices = await connectedDevices() else { return .success(udid) }

        // Either identifier is valid — the CoreDevice UUID or the hardware
        // UDID — but only one of them works as a destination.
        if let match = devices.first(where: { DeviceIdentity.matches($0, udid: udid) }) {
            return .success(DeviceIdentity.destinationUDID(for: match) ?? udid)
        }

        // Offer the destination UDID, since that is what the caller needs
        // to pass to a device tool.
        let candidates = devices.prefix(5).compactMap { device -> String? in
            guard let id = DeviceIdentity.destinationUDID(for: device) else { return nil }
            let name = (device["deviceProperties"] as? [String: Any])?["name"] as? String ?? "Unknown"
            return "  \(id) — \(name)"
        }.joined(separator: "\n")

        return .failure(ToolError(
            code: .staleDefault,
            message: "Device UDID '\(udid)' not found in connected devices. Run list_devices to pick a valid device, then session_set_defaults to update.",
            details: candidates.isEmpty ? nil : "Connected devices:\n\(candidates)"
        ))
    }

    /// Devices reported by `devicectl`, or nil when it can't be queried.
    private func connectedDevices() async -> [[String: Any]]? {
        guard let result = try? await executor.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", "-"],
            timeout: 15,
            environment: nil
        ), result.succeeded, let data = result.stdout.data(using: .utf8) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultObj = json["result"] as? [String: Any],
              let devices = resultObj["devices"] as? [[String: Any]] else { return nil }

        return devices
    }

    /// Validates that a filesystem path exists and is within allowed roots.
    /// Returns nil if valid, ToolError if outside policy or missing.
    public func validatePathExists(
        _ path: String,
        label: String
    ) -> ToolError? {
        if let policyError = pathPolicy?.validate(path, label: label) {
            return policyError
        }

        if fileExists(path) { return nil }

        return ToolError(
            code: .staleDefault,
            message: "\(label) path does not exist: \(path). Run discover_projects to find valid paths, then session_set_defaults to update."
        )
    }
}
