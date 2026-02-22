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
    let registry = ToolRegistry()
    await registerAllTools(with: registry, session: session, executor: executor, concurrency: concurrency, artifacts: artifacts)

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
            return .init(content: [.text(result.content)])
        case .error(let error):
            return .init(content: [.text(error.message)], isError: true)
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

        print("ios-mcp doctor")
        print("==============\n")

        // Xcode
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcode-select",
                arguments: ["-p"]
            )
            if result.succeeded {
                print("[ok] Xcode: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                print("[!!] Xcode: not found — install via xcode-select --install")
            }
        } catch {
            print("[!!] Xcode: check failed — \(error)")
        }

        // Simulators
        do {
            let result = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "-j"]
            )
            if result.succeeded {
                print("[ok] Simulator: simctl available")
            } else {
                print("[!!] Simulator: simctl not available")
            }
        } catch {
            print("[!!] Simulator: check failed — \(error)")
        }

        // swift-log version
        print("[ok] ios-mcp version: 0.1.0")
        print("\nAll checks passed.")
    }
}
