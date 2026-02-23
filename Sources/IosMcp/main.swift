//
//  main.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import ArgumentParser
import Core
import Foundation
import Logging
import MCP
import Tools

@main
struct IosMcpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ios-mcp",
        abstract: "MCP server for headless iOS development",
        version: "0.1.0",
        subcommands: [Doctor.self],
        defaultSubcommand: nil
    )

    func run() async throws {
        try await startServer()
    }
}

// MARK: - MCP Server

private func startServer() async throws {
    LoggingConfiguration.bootstrap(level: .info)
    let logger = Logger(label: "ios-mcp")

    let session = SessionStore()
    let executor = CommandExecutor()
    let concurrency = ConcurrencyPolicy()
    let artifacts = ArtifactStore(
        baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ios-mcp-artifacts")
    )
    let logCapture = LogCaptureManager()
    let debugSession = LLDBSessionManager()
    try? await artifacts.cleanupStaleDirectories()

    let pathPolicy = PathPolicy()
    let validator = DefaultsValidator(executor: executor, pathPolicy: pathPolicy)

    let registry = ToolRegistry()
    await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, logCapture: logCapture, debugSession: debugSession, validator: validator)

    let server = Server(
        name: "ios-mcp",
        version: "0.1.0",
        capabilities: .init(tools: .init())
    )

    await server.withMethodHandler(ListTools.self) { _ in
        let manifests = await registry.listTools()
        return .init(tools: manifests.map { $0.mcpTool() })
    }

    await server.withMethodHandler(CallTool.self) { params in
        let response = try await registry.callTool(
            name: params.name,
            arguments: params.arguments ?? [:]
        )
        switch response {
        case .success(let result):
            var content: [Tool.Content] = [.text(result.content)]
            if result.inlineArtifacts {
                for artifact in result.artifacts where artifact.mimeType.hasPrefix("image/") {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: artifact.path)) {
                        content.append(.image(
                            data: data.base64EncodedString(),
                            mimeType: artifact.mimeType,
                            metadata: nil
                        ))
                    }
                }
            }
            let steps = await NextStepResolver.resolve(for: params.name, session: session)
            if !steps.isEmpty {
                let lines = steps.enumerated().map { idx, step in
                    var line = "\(idx + 1). \(step.tool) — \(step.description)"
                    if !step.context.isEmpty {
                        let pairs = step.context.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key)=\($0.value)" }
                            .joined(separator: ", ")
                        line += " (\(pairs))"
                    }
                    return line
                }
                content.append(.text("\nSuggested next steps:\n" + lines.joined(separator: "\n")))
            }
            return .init(content: content)
        case .error(let error):
            var content: [Tool.Content] = [.text(error.message)]
            if let details = error.details {
                content.append(.text(details))
            }
            return .init(content: content, isError: true)
        }
    }

    // Periodic artifact cleanup every 30 minutes
    Task.detached {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1800))
            await artifacts.evictExpired()
            try? await artifacts.cleanupStaleDirectories()
        }
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)
    logger.info("ios-mcp server started on stdio")

    // Keep the server running until the transport closes.
    await server.waitUntilCompleted()
}

// MARK: - Doctor Subcommand

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check environment dependencies for ios-mcp"
    )

    func run() async throws {
        let executor = CommandExecutor()
        var requiredFailed = false
        var optionalFailed = false

        print("ios-mcp doctor")
        print("==============\n")

        // Xcode (required)
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcode-select",
                arguments: ["-p"],
                timeout: 10
            )
            if result.succeeded {
                print("[ok] Xcode: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                print("[!!] Xcode: not found — install via xcode-select --install")
                requiredFailed = true
            }
        } catch {
            print("[!!] Xcode: check failed — \(error)")
            requiredFailed = true
        }

        // Simulators (required)
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "-j"],
                timeout: 15
            )
            if result.succeeded {
                print("[ok] Simulator: simctl available")
            } else {
                print("[!!] Simulator: simctl not available")
                requiredFailed = true
            }
        } catch {
            print("[!!] Simulator: check failed — \(error)")
            requiredFailed = true
        }

        // LLDB (required)
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["lldb", "--version"],
                timeout: 10
            )
            if result.succeeded {
                let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[ok] LLDB: \(version)")
            } else {
                print("[!!] LLDB: not available")
                requiredFailed = true
            }
        } catch {
            print("[!!] LLDB: check failed — \(error)")
            requiredFailed = true
        }

        // axe (optional)
        switch resolveAxePath() {
        case .success(let path):
            do {
                let result = try await executor.execute(
                    executable: path,
                    arguments: ["--version"],
                    timeout: 10
                )
                if result.succeeded {
                    let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let checksumStatus = verifyAxeChecksum(binaryPath: path)
                    print("[ok] axe: \(version)\(checksumStatus)")
                } else {
                    print("[--] axe: found at \(path) but --version failed")
                    optionalFailed = true
                }
            } catch {
                print("[--] axe: check failed — \(error)")
                optionalFailed = true
            }
        case .failure:
            print("[--] axe: not found — UI automation tools will be unavailable")
            optionalFailed = true
        }

        // SwiftLint (optional)
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/which",
                arguments: ["swiftlint"],
                timeout: 5
            )
            if result.succeeded {
                let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[ok] SwiftLint: \(path)")
            } else {
                print("[--] SwiftLint: not found — lint tool will be unavailable")
                optionalFailed = true
            }
        } catch {
            print("[--] SwiftLint: check failed — \(error)")
            optionalFailed = true
        }

        // Version
        print("[ok] ios-mcp version: 0.1.0")

        // Verdict
        if requiredFailed {
            print("\nVerdict: UNSUPPORTED — required dependencies are missing.")
        } else if optionalFailed {
            print("\nVerdict: WARNING — optional dependencies are missing. Some tools will be unavailable.")
        } else {
            print("\nVerdict: SUPPORTED — all checks passed.")
        }
    }
}

// MARK: - Axe Checksum Verification

/// Verifies the axe binary checksum against a sibling `.sha256` file.
/// Returns a status string to append to the doctor output line.
private func verifyAxeChecksum(binaryPath: String) -> String {
    let binaryURL = URL(fileURLWithPath: binaryPath)

    // Only verify for vendored binaries (under Vendor/axe/)
    guard binaryPath.contains("Vendor/axe/") else { return "" }

    let checksumURL = binaryURL.deletingLastPathComponent().appendingPathComponent("axe.sha256")
    guard let checksumContents = try? String(contentsOf: checksumURL, encoding: .utf8) else {
        return " [--] checksum file not found"
    }

    // Parse "binary_sha256=<hex>" line
    var expectedHash: String?
    for line in checksumContents.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("binary_sha256=") {
            expectedHash = String(trimmed.dropFirst("binary_sha256=".count))
            break
        }
    }

    guard let expected = expectedHash, !expected.isEmpty else {
        return " [--] checksum file missing binary_sha256 entry"
    }

    // Compute actual SHA-256 via shasum
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
    process.arguments = ["-a", "256", binaryPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return " [--] checksum computation failed" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // shasum output format: "<hash>  <path>"
        let actualHash = output.components(separatedBy: " ").first ?? ""
        if actualHash.lowercased() == expected.lowercased() {
            return " [ok] checksum verified"
        } else {
            return " [--] checksum mismatch"
        }
    } catch {
        return " [--] checksum verification failed"
    }
}
