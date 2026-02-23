//
//  TestSimTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation
import MCP

func registerTestSimTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    concurrency: ConcurrencyPolicy,
    artifacts: ArtifactStore,
    validator: DefaultsValidator,
    progressReporter: ProgressReporter? = nil
) async {
    let manifest = ToolManifest(
        name: "test_sim",
        description: "Run tests for an Xcode project on the iOS Simulator. Falls back to session defaults for workspace, project, scheme, configuration, udid, and derived_data_path. Returns pass/fail/skip counts and failing test names.",
        inputSchema: JSONSchema(
            properties: [
                "workspace": .init(
                    type: "string",
                    description: "Path to .xcworkspace. Falls back to session default."
                ),
                "project": .init(
                    type: "string",
                    description: "Path to .xcodeproj. Falls back to session default. Ignored if workspace is provided."
                ),
                "scheme": .init(
                    type: "string",
                    description: "Scheme name. Falls back to session default."
                ),
                "configuration": .init(
                    type: "string",
                    description: "Build configuration (e.g., Debug, Release). Falls back to session default, then Debug."
                ),
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "derived_data_path": .init(
                    type: "string",
                    description: "Custom DerivedData path. Falls back to session default."
                ),
                "extra_args": .init(
                    type: "string",
                    description: "Additional xcodebuild arguments, space-separated."
                ),
                "test_plan": .init(
                    type: "string",
                    description: "Test plan name to use."
                ),
                "only_testing": .init(
                    type: "string",
                    description: "Only run specified tests (e.g., 'MyTests/testFoo'). Comma-separated for multiple."
                ),
                "skip_testing": .init(
                    type: "string",
                    description: "Skip specified tests (e.g., 'MyTests/testSlow'). Comma-separated for multiple."
                ),
            ]
        ),
        category: .build
    )

    await registry.register(manifest: manifest) { args in
        let resolved: ResolvedBuildArgs
        switch await resolveBuildArgs(from: args, session: session, validator: validator) {
        case .success(let r): resolved = r
        case .failure(let error): return .error(error)
        }

        return await concurrency.withLock(
            key: resolved.lockKey,
            owner: "test_sim"
        ) {
            do {
                let timestamp = Int(Date().timeIntervalSince1970)
                let resultPath = NSTemporaryDirectory() + "\(resolved.scheme)_test_\(timestamp).xcresult"

                try? FileManager.default.removeItem(atPath: resultPath)

                var testArgs = xcodebuildBaseArgs(from: resolved, resultBundlePath: resultPath)
                testArgs.append("test")

                if case .string(let plan) = args["test_plan"] {
                    testArgs += ["-testPlan", plan]
                }

                if case .string(let only) = args["only_testing"] {
                    for target in only.components(separatedBy: ",") {
                        let trimmed = target.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { testArgs += ["-only-testing:\(trimmed)"] }
                    }
                }

                if case .string(let skip) = args["skip_testing"] {
                    for target in skip.components(separatedBy: ",") {
                        let trimmed = target.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { testArgs += ["-skip-testing:\(trimmed)"] }
                    }
                }

                let timeout: TimeInterval = min(
                    args["timeout"].flatMap { if case .int(let t) = $0 { Double(t) } else { nil } } ?? 1800,
                    3600
                )

                let testStart = ContinuousClock.now
                let phaseParser = XcodebuildPhaseParser()
                let result = try await executor.executeStreaming(
                    executable: "/usr/bin/xcodebuild",
                    arguments: testArgs,
                    timeout: timeout,
                    environment: nil
                ) { line in
                    if let phase = await phaseParser.parse(line: line), let reporter = progressReporter {
                        let elapsed = ContinuousClock.now - testStart
                        let msg = String(format: "%@ — %.0fs", phase, durationSeconds(elapsed))
                        await reporter.report(message: msg)
                    }
                }

                let diagnostics = await fetchBuildDiagnostics(
                    resultBundlePath: resultPath,
                    executor: executor
                )
                let testResults = await fetchTestResults(
                    resultBundlePath: resultPath,
                    executor: executor
                )
                let elapsed = ContinuousClock.now - testStart

                var lines: [String] = []

                if result.succeeded {
                    lines.append("Tests passed for scheme '\(resolved.scheme)'.")
                } else {
                    lines.append("Tests failed for scheme '\(resolved.scheme)'.")
                }

                lines.append(String(format: "Elapsed: %.1fs", durationSeconds(elapsed)))

                lines.append("Results: \(testResults.passed) passed, \(testResults.failed) failed, \(testResults.skipped) skipped (total: \(testResults.totalTests))")

                for failure in testResults.failedTests {
                    var failLine = "  FAIL: \(failure.name)"
                    if let msg = failure.message { failLine += " — \(msg)" }
                    lines.append(failLine)
                }

                if diagnostics.errors.count > 0 {
                    lines.append("Build errors: \(diagnostics.errors.count)")
                    for error in diagnostics.errors {
                        lines.append("  error: \(error.message)")
                    }
                }

                lines.append("xcresult: \(resultPath)")

                if result.succeeded {
                    return .success(ToolResult(content: lines.joined(separator: "\n")))
                } else {
                    return .error(ToolError(
                        code: .commandFailed,
                        message: lines.joined(separator: "\n"),
                        details: result.stderr
                    ))
                }
            } catch let error as ToolError {
                return .error(error)
            } catch {
                return .error(ToolError(
                    code: .internalError,
                    message: "Test run failed: \(error.localizedDescription)"
                ))
            }
        }
    }
}
