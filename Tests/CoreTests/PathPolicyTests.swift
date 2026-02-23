//
//  PathPolicyTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("PathPolicy")
struct PathPolicyTests {

    @Test("Allows paths under home directory")
    func allowsHomePaths() {
        let policy = PathPolicy()
        let home = NSHomeDirectory()
        let error = policy.validate(home + "/Projects/MyApp", label: "Workspace")
        #expect(error == nil)
    }

    @Test("Allows paths under /tmp")
    func allowsTmpPaths() {
        let policy = PathPolicy()
        let error = policy.validate("/tmp/ios-mcp-test", label: "Temp")
        #expect(error == nil)
    }

    @Test("Allows paths under /private/tmp")
    func allowsPrivateTmpPaths() {
        let policy = PathPolicy()
        let error = policy.validate("/private/tmp/ios-mcp-test", label: "Temp")
        #expect(error == nil)
    }

    @Test("Allows paths under /var/folders")
    func allowsVarFoldersPaths() {
        let policy = PathPolicy()
        let error = policy.validate("/var/folders/ab/cd/T/test", label: "Temp")
        #expect(error == nil)
    }

    @Test("Allows NSTemporaryDirectory paths")
    func allowsNSTemporaryDirectory() {
        let policy = PathPolicy()
        let tmp = NSTemporaryDirectory() + "test-file"
        let error = policy.validate(tmp, label: "Temp")
        #expect(error == nil)
    }

    @Test("Rejects /etc/passwd")
    func rejectsEtcPasswd() {
        let policy = PathPolicy()
        let error = policy.validate("/etc/passwd", label: "Config")
        #expect(error != nil)
        #expect(error?.code == .invalidInput)
        #expect(error?.message.contains("outside allowed directories") == true)
    }

    @Test("Rejects /usr/local/bin")
    func rejectsUsrLocalBin() {
        let policy = PathPolicy()
        let error = policy.validate("/usr/local/bin/something", label: "Binary")
        #expect(error != nil)
        #expect(error?.code == .invalidInput)
    }

    @Test("Rejects root path /")
    func rejectsRootPath() {
        let policy = PathPolicy()
        let error = policy.validate("/", label: "Root")
        #expect(error != nil)
    }

    @Test("Custom allowed roots override defaults")
    func customAllowedRoots() {
        let policy = PathPolicy(allowedRoots: ["/opt/custom"])
        // Default paths should be rejected
        let homeError = policy.validate(NSHomeDirectory() + "/test", label: "Home")
        #expect(homeError != nil)

        // Custom root should be allowed
        let customError = policy.validate("/opt/custom/project", label: "Custom")
        #expect(customError == nil)
    }

    @Test("Path policy integrated into DefaultsValidator")
    func integratedWithValidator() {
        let policy = PathPolicy()
        let validator = DefaultsValidator(
            executor: MockPolicyValidator.executor(stdout: ""),
            fileExists: { _ in true },
            pathPolicy: policy
        )

        // Allowed path passes both policy and existence
        let okError = validator.validatePathExists(NSHomeDirectory() + "/Projects", label: "Workspace")
        #expect(okError == nil)

        // Disallowed path fails policy before existence check
        let policyError = validator.validatePathExists("/etc/passwd", label: "Config")
        #expect(policyError != nil)
        #expect(policyError?.code == .invalidInput)
    }
}

// MARK: - Helpers

private enum MockPolicyValidator {
    struct Executor: CommandExecuting {
        let handler: @Sendable (String, [String]) async throws -> CommandResult

        func execute(
            executable: String,
            arguments: [String],
            timeout: TimeInterval?,
            environment: [String: String]?
        ) async throws -> CommandResult {
            try await handler(executable, arguments)
        }
    }

    static func executor(stdout: String) -> Executor {
        Executor { _, _ in
            CommandResult(stdout: stdout, stderr: "", exitCode: 0)
        }
    }
}
