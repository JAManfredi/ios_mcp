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
        version: "0.3.4",
        subcommands: [Doctor.self],
        defaultSubcommand: nil
    )

    @Option(name: .long, help: "Opt in to native Xcode inspect_ui and tap using this absolute .xcodeproj/.xcworkspace path. Requires Xcode agent approval; other UI tools still use AXe.")
    var nativeUIWorkspace: String?

    func run() async throws {
        try await startServer(nativeUIWorkspace: nativeUIWorkspace)
    }
}

// MARK: - MCP Server

private func startServer(nativeUIWorkspace: String?) async throws {
    LoggingConfiguration.bootstrap(level: .info)
    let logger = Logger(label: "ios-mcp")

    let session = SessionStore()
    let executor = CommandExecutor()
    let concurrency = ConcurrencyPolicy()
    let artifacts = ArtifactStore(
        baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ios-mcp-artifacts")
    )
    let nativeUI: NativeUIController?
    do {
        nativeUI = try nativeUIWorkspace.map {
            try NativeUIController(workspace: $0, artifacts: artifacts, concurrency: concurrency)
        }
    } catch let error as ToolError {
        throw ValidationError(error.message)
    }
    let logCapture = LogCaptureManager()
    let debugSession = LLDBSessionManager()
    let videoRecording = VideoRecordingManager()
    try? await artifacts.cleanupStaleDirectories()

    let pathPolicy = PathPolicy()
    let validator = DefaultsValidator(executor: executor, pathPolicy: pathPolicy)
    let navGraph = NavGraphStore()

    let server = Server(
        name: "ios-mcp",
        version: "0.3.4",
        capabilities: .init(tools: .init())
    )

    let progressReporter = Core.ProgressReporter { token, progress, total, message in
        let params = ProgressNotification.Parameters(
            progressToken: token,
            progress: progress,
            total: total,
            message: message
        )
        try? await server.notify(ProgressNotification.message(params))
    }

    let registry = ToolRegistry()
    await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts, logCapture: logCapture, debugSession: debugSession, validator: validator, videoRecording: videoRecording, navGraph: navGraph, progressReporter: progressReporter, nativeUI: nativeUI)

    await server.withMethodHandler(ListTools.self) { _ in
        let manifests = await registry.listTools()
        return .init(tools: manifests.map { $0.mcpTool() })
    }

    await server.withMethodHandler(CallTool.self) { params in
        await progressReporter.setToken(params._meta?.progressToken)

        let response: ToolResponse
        do {
            response = try await registry.callTool(
                name: params.name,
                arguments: params.arguments ?? [:]
            )
        } catch {
            await progressReporter.setToken(nil)
            throw error
        }
        await progressReporter.setToken(nil)

        switch response {
        case .success(let result):
            var content: [Tool.Content] = []
            if result.unsafeCommandExecuted {
                content.append(.text("{\"unsafeCommandExecuted\":true}"))
            }
            content.append(.text(result.content))
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

    // Cleanup: tear down active sessions, log captures, and locks
    await nativeUI?.shutdown()
    await debugSession.teardownAll()
    await logCapture.stopAll()
    await videoRecording.stopAll()
    await concurrency.releaseAll()
    logger.info("ios-mcp server shut down")
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

        // macOS version (required: 14+)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        if osVersion.majorVersion >= 14 {
            print("[ok] macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        } else {
            print("[!!] macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion) — requires macOS 14+")
            requiredFailed = true
        }

        // Xcode (required: path exists)
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

        // Xcode version (required: 16+)
        var xcodeVersion: String?
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcodebuild",
                arguments: ["-version"],
                timeout: 10
            )
            if result.succeeded {
                let firstLine = result.stdout.components(separatedBy: .newlines).first ?? ""
                // Expected format: "Xcode 16.2"
                let parts = firstLine.components(separatedBy: " ")
                if parts.count >= 2,
                   let majorVersion = Int(parts[1].components(separatedBy: ".").first ?? "") {
                    xcodeVersion = parts[1]
                    if majorVersion >= 16 {
                        print("[ok] Xcode version: \(parts[1])")
                    } else {
                        print("[!!] Xcode version: \(parts[1]) — requires Xcode 16+")
                        requiredFailed = true
                    }
                } else {
                    print("[--] Xcode version: could not parse '\(firstLine)'")
                }
            } else {
                print("[!!] Xcode version: xcodebuild -version failed")
                requiredFailed = true
            }
        } catch {
            print("[!!] Xcode version: check failed — \(error)")
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
                    if let upgrade = axeVersionWarning(reported: version) {
                        // Under Xcode 27 an old axe can't load SimulatorKit at
                        // all, so every UI tool fails: that's not optional.
                        if let xcodeVersion, !isVersion(xcodeVersion, olderThan: "27") {
                            print("[!!] axe: \(version)\(checksumStatus) — \(upgrade)")
                            requiredFailed = true
                        } else {
                            print("[--] axe: \(version)\(checksumStatus) — \(upgrade)")
                            optionalFailed = true
                        }
                    } else {
                        print("[ok] axe: \(version)\(checksumStatus)")
                    }
                } else {
                    print("[--] axe: \(axeFailureDetail(binaryPath: path, failure: result.stderr))")
                    optionalFailed = true
                }
            } catch {
                print("[--] axe: \(axeFailureDetail(binaryPath: path, failure: "\(error)")) (\(error))")
                optionalFailed = true
            }
        case .failure:
            print("[--] axe: not found — UI automation tools will be unavailable")
            optionalFailed = true
        }

        // devicectl (optional — for physical device support)
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["devicectl", "list", "devices", "--json-output", "-"],
                timeout: 10
            )
            if result.succeeded {
                print("[ok] devicectl: available (physical device support)")
            } else {
                print("[--] devicectl: not available — physical device tools will be unavailable")
                optionalFailed = true
            }
        } catch {
            print("[--] devicectl: check failed — \(error)")
            optionalFailed = true
        }

        // Xcode 27 toolchain features, so a missing tool reads as a version gap
        // rather than a bug.
        if let xcodeVersion {
            let has27 = !isVersion(xcodeVersion, olderThan: "27")
            let has266 = !isVersion(xcodeVersion, olderThan: "26.6")
            func feature(_ name: String, _ available: Bool, _ needs: String) {
                print(available ? "[ok] \(name)" : "[--] \(name): needs Xcode \(needs)")
            }
            feature("Device Hub (open_simulator)", has27, "27+; falls back to Simulator.app")
            feature("devicectl capture (device_screenshot, device recording)", has266, "26.6+")
            feature("Simulator orientation (set_orientation)", has27, "27+")
            feature("simctl reboot (reboot_simulator)", has27, "27+")
            if has27 && osVersion.majorVersion < 26 {
                print("[!!] macOS: Xcode 27 requires macOS Tahoe 26.6 or later")
                requiredFailed = true
            }
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

        // Native servers are optional candidates, not dependencies of our current tools.
        for line in try await NativeMCPDiagnostics.run(executor: executor) {
            print(line)
        }

        // Version
        print("[ok] ios-mcp version: \(IosMcpCommand.configuration.version)")

        // Verdict
        if requiredFailed {
            print("\nVerdict: UNSUPPORTED — required dependencies are missing.")
        } else if optionalFailed {
            print("\nVerdict: WARNING — optional dependencies are missing. Some tools will be unavailable.")
        } else {
            print("\nVerdict: SUPPORTED — required and optional dependencies are available.")
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
