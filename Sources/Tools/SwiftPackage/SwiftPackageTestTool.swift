//
//  SwiftPackageTestTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerSwiftPackageTestTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "swift_package_test",
        description: "Run a Swift package's tests with `swift test` (XCTest and Swift Testing) on the host. Supports filtering and parallel runs. Repetition is supported only for Swift Testing tests (Xcode 27 toolchain). Falls back to session workspace or project parent directory for the package path.",
        inputSchema: JSONSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the Swift package directory containing Package.swift. Falls back to session workspace or project parent directory."
                ),
                "filter": .init(
                    type: "string",
                    description: "Run only tests matching this regular expression (e.g. 'MyTests.testFoo' or 'MyTests')."
                ),
                "skip": .init(
                    type: "string",
                    description: "Skip tests matching this regular expression."
                ),
                "parallel": .init(type: "boolean", description: "Run tests in parallel."),
                "repeat_until": .init(
                    type: "string",
                    description: "Repeat each matching Swift Testing test until it passes or fails (Swift 6.4 / Xcode 27+). Does not repeat XCTest tests. Use 'fail' to reproduce a flaky test.",
                    enumValues: ["pass", "fail"]
                ),
                "maximum_repetitions": .init(
                    type: "integer",
                    description: "Upper bound on repetitions when repeat_until is set. Default: 10."
                ),
                "enable_code_coverage": .init(type: "boolean", description: "Collect code coverage."),
                "timeout": .init(type: "integer", description: "Timeout in whole seconds (default 900, clamped to 1–3600)."),
            ]
        ),
        category: .swiftPackage
    )

    await registry.register(manifest: manifest) { args in
        let packagePath: String
        switch await resolvePackagePath(from: args, session: session, validator: validator) {
        case .success(let path): packagePath = path
        case .failure(let error): return .error(error)
        }

        let options: SwiftTestOptions
        switch SwiftTestOptions.parse(args) {
        case .success(let parsed): options = parsed
        case .failure(let error): return .error(error)
        }

        return await concurrency.withLock(key: "swiftpm:\(packagePath)", owner: "swift_package_test") {
            do {
                let result = try await executor.execute(
                    executable: "/usr/bin/swift",
                    arguments: options.arguments(packagePath: packagePath),
                    timeout: options.timeout,
                    environment: nil
                )

                let combined = result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)
                let summary = summarizeSwiftTestOutput(combined)
                var lines = [
                    result.succeeded ? "swift test passed." : "swift test failed (exit \(result.exitCode)).",
                    "Package path: \(packagePath)",
                ]
                if !summary.isEmpty { lines.append("\n" + summary.joined(separator: "\n")) }
                lines.append("\n--- Output (last 80 lines) ---")
                lines.append(combined.split(separator: "\n", omittingEmptySubsequences: false).suffix(80).joined(separator: "\n"))

                if result.succeeded {
                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                }
                return .error(ToolError(
                    code: .commandFailed,
                    message: lines.prefix(3).joined(separator: "\n"),
                    details: lines.dropFirst(3).joined(separator: "\n")
                ))
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Failed to run swift test: \(error.localizedDescription)"
                ))
            }
        }
    }
}

struct SwiftTestOptions: Equatable, Sendable {
    var filter: String?
    var skip: String?
    var parallel = false
    var repeatUntil: String?
    var maximumRepetitions: Int?
    var enableCodeCoverage = false
    var timeout: TimeInterval = 900

    static func parse(_ args: [String: Value]) -> Result<SwiftTestOptions, ToolError> {
        var options = SwiftTestOptions()
        if case .string(let f) = args["filter"], !f.isEmpty { options.filter = f }
        if case .string(let s) = args["skip"], !s.isEmpty { options.skip = s }
        if case .bool(let p) = args["parallel"] { options.parallel = p }
        if case .bool(let c) = args["enable_code_coverage"] { options.enableCodeCoverage = c }

        if case .string(let r) = args["repeat_until"] {
            guard r == "pass" || r == "fail" else {
                return .failure(ToolError(code: .invalidInput, message: "repeat_until must be 'pass' or 'fail'."))
            }
            options.repeatUntil = r
            options.maximumRepetitions = 10
        }
        if let value = args["maximum_repetitions"] {
            let max: Int
            switch integerArgument(value, named: "maximum_repetitions") {
            case .success(let integer): max = integer
            case .failure(let error): return .failure(error)
            }
            guard options.repeatUntil != nil else {
                return .failure(ToolError(code: .invalidInput, message: "maximum_repetitions requires repeat_until."))
            }
            guard (1...1000).contains(max) else {
                return .failure(ToolError(code: .invalidInput, message: "maximum_repetitions must be between 1 and 1000."))
            }
            options.maximumRepetitions = max
        }
        if let value = args["timeout"] {
            let t: Int
            switch integerArgument(value, named: "timeout") {
            case .success(let integer): t = integer
            case .failure(let error): return .failure(error)
            }
            options.timeout = TimeInterval(min(max(t, 1), 3600))
        }
        return .success(options)
    }

    func arguments(packagePath: String) -> [String] {
        var args = ["test", "--package-path", packagePath]
        if let filter { args += ["--filter", filter] }
        if let skip { args += ["--skip", skip] }
        if parallel { args.append("--parallel") }
        if let repeatUntil, let maximumRepetitions {
            args += ["--maximum-repetitions", String(maximumRepetitions), "--repeat-until", repeatUntil]
        }
        if enableCodeCoverage { args.append("--enable-code-coverage") }
        return args
    }

}

/// Pulls the result lines out of `swift test` output: XCTest's
/// "Executed N tests" totals, Swift Testing's "Test run with N tests"
/// summary, and every failing test line.
func summarizeSwiftTestOutput(_ output: String) -> [String] {
    var summary: [String] = []
    var failures: [String] = []
    for raw in output.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Executed ") && line.contains(" test") {
            summary.append(line)
        } else if line.contains("Test run with ") {
            summary.append(line)
        } else if line.contains(": error: ") || (line.contains("Test ") && line.contains(" failed")) {
            failures.append(line)
        }
    }
    // XCTest prints a running total per suite; the last one is the overall.
    var result = Array(summary.suffix(2))
    if !failures.isEmpty {
        result.append("Failures (\(failures.count)):")
        result += failures.prefix(30).map { "  \($0)" }
        if failures.count > 30 { result.append("  ... and \(failures.count - 30) more") }
    }
    return result
}
