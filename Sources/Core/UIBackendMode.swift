// Created by Jared Manfredi

import Foundation

public enum UIBackendMode: String, Sendable, CaseIterable {
    case auto, native, axe

    /// Preserve the original workspace-only opt-in and the existing AXe default.
    public static func resolve(_ requested: String?, workspace: String?) throws -> UIBackendMode {
        guard let requested else { return workspace == nil ? .axe : .native }
        guard let mode = UIBackendMode(rawValue: requested) else {
            throw ToolError(code: .invalidInput, message: "--ui-backend must be auto, native, or axe.")
        }
        guard mode != .axe || workspace == nil else {
            throw ToolError(code: .invalidInput, message: "--native-ui-workspace cannot be combined with --ui-backend axe.")
        }
        return mode
    }
}

/// Only emitted before native workspace/session/action calls. Tool handlers may
/// select AXe for this signal, never for a generic dependency or action error.
public struct NativeUIUnavailable: Error, Sendable {
    public let reason: String
    init(_ reason: String) { self.reason = reason }
}
