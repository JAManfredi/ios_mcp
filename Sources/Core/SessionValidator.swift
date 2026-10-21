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
    private let cache: ValidationCache

    public init(
        executor: any CommandExecuting,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        pathPolicy: PathPolicy? = nil,
        cacheTTL: TimeInterval = 5
    ) {
        self.executor = executor
        self.fileExists = fileExists
        self.pathPolicy = pathPolicy
        self.cache = ValidationCache(ttl: cacheTTL)
    }

    /// Validates that a simulator UDID exists in `simctl list devices`.
    /// Returns nil if valid or if simctl fails (graceful degradation).
    public func validateSimulatorUDID(_ udid: String) async -> ToolError? {
        // Nearly every simulator tool validates first, and `simctl list` costs
        // hundreds of milliseconds with several runtimes installed. A recent
        // sighting is enough; a miss always re-queries, so a newly created
        // simulator is never rejected from a stale list.
        if await cache.knowsSimulator(udid) { return nil }

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
            await cache.storeSimulators(Set(allDevices.map(\.udid)))

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
        // `devicectl list devices` can take seconds; reuse a recent answer.
        if let canonical = await cache.canonicalDevice(for: udid) { return .success(canonical) }

        guard let devices = await connectedDevices() else { return .success(udid) }

        var aliases: [String: String] = [:]
        for device in devices {
            guard let destination = DeviceIdentity.destinationUDID(for: device) else { continue }
            for identifier in DeviceIdentity.identifiers(for: device) {
                aliases[identifier.lowercased()] = destination
            }
        }
        await cache.storeDevices(aliases)

        // Either identifier is valid — the CoreDevice UUID or the hardware
        // UDID — but only one of them works as a destination.
        if let match = devices.first(where: { DeviceIdentity.matches($0, udid: udid) }) {
            return .success(DeviceIdentity.destinationUDID(for: match) ?? udid)
        }

        // Offer the destination UDID, since that is what the caller needs
        // to pass to a device tool.
        let candidates = devices.prefix(5).compactMap { device -> String? in
            guard let id = DeviceIdentity.destinationUDID(for: device) else { return nil }
            let name = DeviceIdentity.name(for: device) ?? "Unknown"
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
        ), result.succeeded else { return nil }

        return DeviceIdentity.physicalDevices(fromDevicectlJSON: result.stdout)
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

/// Short-lived memory of identifiers recently confirmed by `simctl` and
/// `devicectl`. Only positive answers are cached.
actor ValidationCache {
    private let ttl: TimeInterval
    private var simulators: Set<String> = []
    private var simulatorsFetchedAt: Date?
    private var deviceAliases: [String: String] = [:]
    private var devicesFetchedAt: Date?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func knowsSimulator(_ udid: String) -> Bool {
        guard isFresh(simulatorsFetchedAt) else { return false }
        return simulators.contains(udid)
    }

    func storeSimulators(_ udids: Set<String>) {
        simulators = udids
        simulatorsFetchedAt = Date()
    }

    func canonicalDevice(for udid: String) -> String? {
        guard isFresh(devicesFetchedAt) else { return nil }
        return deviceAliases[udid.lowercased()]
    }

    func storeDevices(_ aliases: [String: String]) {
        deviceAliases = aliases
        devicesFetchedAt = Date()
    }

    private func isFresh(_ fetchedAt: Date?) -> Bool {
        guard ttl > 0, let fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) < ttl
    }
}
