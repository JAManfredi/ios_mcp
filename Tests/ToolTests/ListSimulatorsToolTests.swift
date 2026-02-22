//
//  ListSimulatorsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("list_simulators")
struct ListSimulatorsToolTests {

    // MARK: - Fixture

    private static let simctlJSON = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
          {
            "udid": "AAAA-1111",
            "name": "iPhone 15",
            "state": "Shutdown",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-15"
          },
          {
            "udid": "BBBB-2222",
            "name": "iPhone 15 Pro",
            "state": "Booted",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
          {
            "udid": "CCCC-3333",
            "name": "iPhone 16",
            "state": "Shutdown",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
          },
          {
            "udid": "DDDD-4444",
            "name": "Broken Sim",
            "state": "Shutdown",
            "isAvailable": false,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
          }
        ]
      }
    }
    """

    // MARK: - Parser Tests

    @Test("Parses simctl JSON into SimulatorInfo array")
    func parseHappyPath() throws {
        let data = Self.simctlJSON.data(using: .utf8)!
        let sims = try parseSimctlDevices(data)

        #expect(sims.count == 4)
        let udids = Set(sims.map(\.udid))
        #expect(udids.contains("AAAA-1111"))
        #expect(udids.contains("BBBB-2222"))
        #expect(udids.contains("CCCC-3333"))
        #expect(udids.contains("DDDD-4444"))
    }

    @Test("Parses empty devices")
    func parseEmpty() throws {
        let json = """
        { "devices": {} }
        """
        let sims = try parseSimctlDevices(json.data(using: .utf8)!)
        #expect(sims.isEmpty)
    }

    @Test("Extracts runtime display name")
    func runtimeExtraction() {
        #expect(runtimeDisplayName(from: "com.apple.CoreSimulator.SimRuntime.iOS-18-0") == "iOS 18.0")
        #expect(runtimeDisplayName(from: "com.apple.CoreSimulator.SimRuntime.iOS-17-5") == "iOS 17.5")
        #expect(runtimeDisplayName(from: "unknown-format") == "unknown-format")
    }

    // MARK: - Integration Tests

    @Test("Default filters hide unavailable devices")
    func defaultFiltering() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(Self.simctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(name: "list_simulators", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("3 simulator(s)"))
            #expect(!result.content.contains("Broken Sim"))
            #expect(result.content.contains("iPhone 15"))
            #expect(result.content.contains("iPhone 16"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("show_unavailable includes all devices")
    func showUnavailable() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(Self.simctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(
            name: "list_simulators",
            arguments: ["show_unavailable": .bool(true)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("4 simulator(s)"))
            #expect(result.content.contains("Broken Sim"))
            #expect(result.content.contains("(unavailable)"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Filters by runtime substring")
    func runtimeFilter() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(Self.simctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(
            name: "list_simulators",
            arguments: ["runtime": .string("iOS 18")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("1 simulator(s)"))
            #expect(result.content.contains("iPhone 16"))
            #expect(!result.content.contains("iPhone 15"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Filters by state")
    func stateFilter() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(Self.simctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(
            name: "list_simulators",
            arguments: ["state": .string("Booted")]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("1 simulator(s)"))
            #expect(result.content.contains("iPhone 15 Pro"))
        } else {
            Issue.record("Expected success response")
        }
    }

    @Test("Auto-sets simulator_udid when exactly one booted device")
    func autoSetUDID() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(Self.simctlJSON)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(name: "list_simulators", arguments: [:])

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: simulator_udid = BBBB-2222"))
        } else {
            Issue.record("Expected success response")
        }

        let udid = await session.get(.simulatorUDID)
        #expect(udid == "BBBB-2222")
    }

    @Test("No auto-set when no booted devices")
    func noAutoSetWhenNoneBooted() async throws {
        let allShutdown = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              {
                "udid": "AAAA-1111",
                "name": "iPhone 16",
                "state": "Shutdown",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              }
            ]
          }
        }
        """

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith(allShutdown)

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        _ = try await registry.callTool(name: "list_simulators", arguments: [:])

        let udid = await session.get(.simulatorUDID)
        #expect(udid == nil)
    }

    @Test("Returns error on simctl failure")
    func commandFailure() async throws {
        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.failingWith(stderr: "simctl error")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy())

        let response = try await registry.callTool(name: "list_simulators", arguments: [:])

        if case .error(let error) = response {
            #expect(error.code == .commandFailed)
        } else {
            Issue.record("Expected error response")
        }
    }
}
