// Created by Jared Manfredi

import Foundation

public enum NativeUITarget: Sendable {
    case identifier(String)
    case label(String)
    case coordinates(x: Double, y: Double)
}

/// Parses Apple's text hierarchy without interpreting property-looking text inside labels.
struct NativeUIHierarchy {
    struct Element {
        let kind: String
        let identifier: String?
        let label: String?
        let frame: CGRect?
        let hitPoint: CGPoint?
        let needsActivation: Bool
        let disabled: Bool
        let incomplete: Bool
    }

    let text: String
    let elements: [Element]

    init(text: String) throws {
        self.text = text
        self.elements = try text.split(separator: "\n").map { line in
            guard let fields = Self.fields(String(line).trimmingCharacters(in: .whitespaces)),
                  let kind = fields.first else {
                throw ToolError(code: .commandFailed, message: "Native UI hierarchy format is unsupported.")
            }
            let frame = fields.compactMap(Self.frame).first
            let hitPoint = fields.first(where: { $0.hasPrefix("hitPoint:") })
                .flatMap { Self.numbers(String($0.dropFirst("hitPoint:".count)), count: 2) }
                .map { CGPoint(x: $0[0], y: $0[1]) }
            return Element(
                kind: kind, identifier: Self.string("identifier", in: fields),
                label: Self.string("label", in: fields), frame: frame, hitPoint: hitPoint,
                needsActivation: fields.contains { $0.hasPrefix("activationBundleId:") },
                disabled: fields.contains { ["Disabled", "isEnabled: false", "enabled: false", "isHittable: false"].contains($0) },
                incomplete: fields.contains { $0.hasPrefix("isRemoteLeafPlaceholder") }
            )
        }
        guard elements.contains(where: { $0.kind == "Window" && $0.frame != nil }) else {
            throw ToolError(code: .commandFailed, message: "Native UI hierarchy has no usable window. Wait for the app to finish launching, then inspect again.")
        }
    }

    func point(for target: NativeUITarget) throws -> CGPoint {
        let point: CGPoint
        switch target {
        case .coordinates(let x, let y):
            guard !elements.contains(where: \.needsActivation) else {
                throw ToolError(code: .invalidInput, message: "Native hierarchy contains overlapping apps that require activation. Activate the intended app and inspect again before using coordinates.")
            }
            point = CGPoint(x: x, y: y)
        case .identifier(let value), .label(let value):
            guard !elements.contains(where: \.incomplete) else {
                throw ToolError(code: .invalidInput, message: "Native hierarchy is incomplete. Activate the intended app and inspect again before tapping by identifier or label.")
            }
            let matches = elements.filter {
                switch target {
                case .identifier: return $0.identifier == value
                default: return $0.label == value
                }
            }
            guard matches.count == 1 else {
                throw ToolError(code: .invalidInput, message: matches.isEmpty
                    ? "Target not found in the native hierarchy. Run inspect_ui to find a visible target."
                    : "Target is ambiguous in the native hierarchy. Use a unique accessibility identifier or explicit coordinates.")
            }
            let match = matches[0]
            guard !match.disabled, !match.needsActivation, let hitPoint = match.hitPoint else {
                throw ToolError(code: .invalidInput, message: "Target has no usable hit point, is disabled, or requires another app to be activated. Activate the intended app and inspect again.")
            }
            point = hitPoint
        }
        guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
              elements.contains(where: { $0.kind == "Window" && $0.frame?.contains(point) == true }) else {
            throw ToolError(code: .invalidInput, message: "Tap coordinates must be finite and inside a window in the current native hierarchy (screen points, not screenshot pixels).")
        }
        return point
    }

    private static func fields(_ line: String) -> [String]? {
        var result: [String] = []
        var field = ""
        var quoted = false
        var escaped = false
        var depth = 0
        for character in line {
            if escaped { field.append(character); escaped = false; continue }
            if quoted && character == "\\" { field.append(character); escaped = true; continue }
            if character == "'" { quoted.toggle() }
            if !quoted {
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
                if depth < 0 { return nil }
                if character == "," && depth == 0 {
                    result.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                    continue
                }
            }
            field.append(character)
        }
        guard !quoted, !escaped, depth == 0 else { return nil }
        result.append(field.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func string(_ key: String, in fields: [String]) -> String? {
        guard let field = fields.first(where: { $0.hasPrefix(key + ": '") }), field.hasSuffix("'") else { return nil }
        return String(field.dropFirst(key.count + 3).dropLast())
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func numbers(_ text: String, count: Int) -> [Double]? {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "{}, "))
            .filter { !$0.isEmpty }
        let values = parts.compactMap(Double.init)
        guard values.count == count, parts.count == count, values.allSatisfy(\.isFinite) else { return nil }
        return values
    }

    private static func frame(_ text: String) -> CGRect? {
        guard text.hasPrefix("{{"), text.hasSuffix("}}"),
              let values = numbers(text, count: 4), values[2] > 0, values[3] > 0,
              (values[0] + values[2]).isFinite, (values[1] + values[3]).isFinite else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}
