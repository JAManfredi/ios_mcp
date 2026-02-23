//
//  RedactorTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core

@Suite("Redactor")
struct RedactorTests {

    @Test("Redacts Bearer tokens")
    func redactsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig"
        let result = Redactor.redact(input)
        #expect(result.contains("Bearer [REDACTED]"))
        #expect(!result.contains("eyJhbGciOiJIUzI1NiJ9"))
    }

    @Test("Redacts API key in key=value format")
    func redactsApiKey() {
        let input = "api_key=sk_live_abc123def456"
        let result = Redactor.redact(input)
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("sk_live_abc123def456"))
    }

    @Test("Redacts password in key: value format")
    func redactsPasswordInKeyValue() {
        let input = "password: super_secret_value"
        let result = Redactor.redact(input)
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("super_secret_value"))
    }

    @Test("Preserves non-sensitive content")
    func preservesNonSensitiveContent() {
        let input = "Build succeeded for scheme 'MyApp'.\nErrors: 0, Warnings: 2"
        let result = Redactor.redact(input)
        #expect(result == input)
    }

    @Test("Handles empty string")
    func handlesEmptyString() {
        let result = Redactor.redact("")
        #expect(result == "")
    }
}
