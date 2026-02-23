//
//  Redactor.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Pattern-based secret redaction for command output.
/// Applied automatically by CommandExecutor to stdout/stderr before returning results.
public enum Redactor {

    // MARK: - Patterns

    private static let bearerPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#)
    }()

    private static let genericSecretPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)(api[_-]?key|secret|token|password|auth)\s*[:=]\s*\S+"#)
    }()

    private static let signingIdentityPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"Signing Identity:\s*"[^"]+""#)
    }()

    private static let provisioningProfilePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"Provisioning Profile:\s*"[^"]+""#)
    }()

    // MARK: - Public API

    /// Redacts secrets from the given text using precompiled patterns.
    /// Returns the text with sensitive values replaced by `[REDACTED]`.
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Bearer tokens
        result = bearerPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "Bearer [REDACTED]"
        )

        // Generic secrets — preserve the key name, redact the value
        result = genericSecretPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1: [REDACTED]"
        )

        // Signing identity
        result = signingIdentityPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "Signing Identity: \"[REDACTED]\""
        )

        // Provisioning profile
        result = provisioningProfilePattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "Provisioning Profile: \"[REDACTED]\""
        )

        return result
    }
}
