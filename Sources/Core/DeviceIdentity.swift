//
//  DeviceIdentity.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// `devicectl` reports two identifiers per device and they are not
/// interchangeable: a CoreDevice UUID under `identifier`, and the hardware UDID.
/// Only the hardware UDID resolves as an `xcodebuild -destination`, while other
/// tooling and older sessions carry the CoreDevice UUID. Both are legitimate
/// handles for the same device, so identity lives here rather than being
/// decided independently at each call site — that split is what let a stored
/// UDID become unrecognisable to the validator that guards every device tool.
///
/// Schema: as of devicectl JSON version 5 (Xcode 27), `hardwareProperties`,
/// `deviceProperties` and `connectionProperties` are deprecated in favour of a
/// single `properties` dictionary and "will be removed in a future release".
/// Every lookup here reads `properties` first and falls back to the legacy
/// fields, so the same code works on Xcode 16 through 27 and keeps working
/// once the legacy fields are gone.
public enum DeviceIdentity {

    /// The identifier `xcodebuild -destination` accepts, or nil when the record
    /// carries neither identifier.
    ///
    /// Optional rather than a `"?"` placeholder: a placeholder is a plausible
    /// string that flows onward and gets stored as a session default, so a
    /// single malformed record poisons every later device call.
    public static func destinationUDID(for device: [String: Any]) -> String? {
        hardwareUDID(for: device) ?? device["identifier"] as? String
    }

    /// Every identifier this device answers to.
    public static func identifiers(for device: [String: Any]) -> [String] {
        var found: [String] = []
        if let identifier = device["identifier"] as? String { found.append(identifier) }
        if let udid = hardwareUDID(for: device), !found.contains(udid) { found.append(udid) }
        return found
    }

    /// Whether `udid` names this device under either identifier.
    public static func matches(_ device: [String: Any], udid: String) -> Bool {
        identifiers(for: device).contains { $0.caseInsensitiveCompare(udid) == .orderedSame }
    }

    // MARK: - Descriptive Properties

    public static func name(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "device", "name"],
            ["properties", "name"],
            ["deviceProperties", "name"],
        ])
    }

    public static func osVersion(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "device", "osVersionNumber"],
            ["properties", "software", "osVersionNumber"],
            ["properties", "osVersionNumber"],
            ["deviceProperties", "osVersionNumber"],
        ]) ?? deepString(in: device["properties"], key: "osVersionNumber")
    }

    public static func model(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "hardware", "marketingName"],
            ["hardwareProperties", "marketingName"],
            ["properties", "hardware", "productType"],
            ["hardwareProperties", "productType"],
        ]) ?? deepString(in: device["properties"], key: "marketingName")
    }

    public static func transportType(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "connection", "transportType"],
            ["connectionProperties", "transportType"],
        ])
    }

    /// `physical` or `simulator` on Xcode 27+ (`properties.hardware.reality`).
    /// Nil on older Xcode, where `list devices` only reported physical devices.
    public static func reality(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "hardware", "reality"],
            ["hardwareProperties", "reality"],
        ])
    }

    /// True for simulator records. Matches on prefix so `simulator` and
    /// `simulated` both count, since the value isn't documented.
    public static func isSimulator(_ device: [String: Any]) -> Bool {
        reality(for: device)?.lowercased().hasPrefix("simul") ?? false
    }

    // MARK: - Parsing

    /// Device records from `devicectl list devices --json-output -`, or nil when
    /// the output isn't the expected JSON envelope.
    public static func devices(fromDevicectlJSON stdout: String) -> [[String: Any]]? {
        guard let data = stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]] else {
            return nil
        }
        return devices
    }

    /// Physical devices only. Xcode 27's devicectl also lists simulators; those
    /// belong to the simulator tools, and a simulator UDID stored as the device
    /// default would send `xcodebuild -destination platform=iOS` to the wrong place.
    public static func physicalDevices(fromDevicectlJSON stdout: String) -> [[String: Any]]? {
        devices(fromDevicectlJSON: stdout)?.filter { !isSimulator($0) }
    }

    // MARK: - Private

    private static func hardwareUDID(for device: [String: Any]) -> String? {
        string(in: device, paths: [
            ["properties", "hardware", "udid"],
            ["properties", "udid"],
            ["hardwareProperties", "udid"],
        ]) ?? deepString(in: device["properties"], key: "udid")
    }

    private static func string(in object: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            var current: Any? = object
            for key in path {
                current = (current as? [String: Any])?[key]
            }
            if let value = current as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Depth-first search for a uniquely named leaf key. Used only for keys
    /// whose name is unambiguous (`udid`, `osVersionNumber`), so a reshuffle of
    /// the `properties` sub-dictionaries in a later devicectl doesn't silently
    /// drop the value.
    private static func deepString(in object: Any?, key: String, depth: Int = 0) -> String? {
        guard depth < 4, let dict = object as? [String: Any] else { return nil }
        if let value = dict[key] as? String, !value.isEmpty { return value }
        for nested in dict.keys.sorted() {
            if let found = deepString(in: dict[nested], key: key, depth: depth + 1) {
                return found
            }
        }
        return nil
    }
}
