//
//  DeviceIdentity.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// `devicectl` reports two identifiers per device and they are not
/// interchangeable: a CoreDevice UUID under `identifier`, and the hardware UDID
/// under `hardwareProperties.udid`. Only the hardware UDID resolves as an
/// `xcodebuild -destination`, while other tooling and older sessions carry the
/// CoreDevice UUID. Both are legitimate handles for the same device, so
/// identity lives here rather than being decided independently at each call
/// site — that split is what let a stored UDID become unrecognisable to the
/// validator that guards every device tool.
public enum DeviceIdentity {

    /// The identifier `xcodebuild -destination` accepts, or nil when the record
    /// carries neither identifier.
    ///
    /// Optional rather than a `"?"` placeholder: a placeholder is a plausible
    /// string that flows onward and gets stored as a session default, so a
    /// single malformed record poisons every later device call.
    public static func destinationUDID(for device: [String: Any]) -> String? {
        let hardware = device["hardwareProperties"] as? [String: Any]
        return hardware?["udid"] as? String ?? device["identifier"] as? String
    }

    /// Every identifier this device answers to.
    public static func identifiers(for device: [String: Any]) -> [String] {
        var found: [String] = []
        if let identifier = device["identifier"] as? String { found.append(identifier) }
        if let hardware = device["hardwareProperties"] as? [String: Any],
           let udid = hardware["udid"] as? String {
            found.append(udid)
        }
        return found
    }

    /// Whether `udid` names this device under either identifier.
    public static func matches(_ device: [String: Any], udid: String) -> Bool {
        identifiers(for: device).contains { $0.caseInsensitiveCompare(udid) == .orderedSame }
    }
}
