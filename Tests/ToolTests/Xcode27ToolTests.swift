//
//  Xcode27ToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

/// Registers every tool against a mock executor, the way the other tool suites do.
private func makeRegistry(
    executor: MockCommandExecutor,
    session: SessionStore = SessionStore(),
    debugSession: MockDebugSession = MockDebugSession(),
    validator: DefaultsValidator = testValidator()
) async -> ToolRegistry {
    let registry = ToolRegistry()
    await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID())")), logCapture: MockLogCapture(), debugSession: debugSession, validator: validator, videoRecording: MockVideoRecording(), navGraph: NavGraphStore())
    return registry
}

@Suite("reboot_simulator")
struct RebootSimulatorToolTests {

    @Test("Runs simctl reboot")
    func reboots() async throws {
        let capture = ArgCapture()
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        })

        let response = try await registry.callTool(name: "reboot_simulator", arguments: ["udid": .string("AAAA-1111")])

        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("rebooted"))
        #expect(await capture.lastArgs == ["simctl", "reboot", "AAAA-1111"])
    }

    @Test("Explains the Xcode requirement on older simctl")
    func olderXcode() async throws {
        let registry = await makeRegistry(executor: .failingWith(stderr: "Unknown subcommand 'reboot'"))

        let response = try await registry.callTool(name: "reboot_simulator", arguments: ["udid": .string("AAAA-1111")])

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.code == .dependencyMissing)
        #expect(error.message.contains("Xcode 27"))
    }
}

@Suite("set_orientation")
struct SetOrientationToolTests {

    @Test("Sets orientation and confirms it by reading back")
    func setsAndVerifies() async throws {
        let calls = AllCallCapture()
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            await calls.capture(args)
            if args.contains("get") {
                return CommandResult(stdout: "deviceOrientation: landscapeLeft\ndeviceIsOrientationLocked: false", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "outcome: success", stderr: "", exitCode: 0)
        })

        let response = try await registry.callTool(
            name: "set_orientation",
            arguments: ["udid": .string("AAAA-1111"), "orientation": .string("landscapeLeft")]
        )

        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("rotated to landscapeLeft"))
        let all = await calls.allArgs
        #expect(all.first == ["devicectl", "device", "orientation", "set", "--device", "AAAA-1111", "landscapeLeft"])
        #expect(all.last == ["devicectl", "device", "orientation", "get", "--device", "AAAA-1111"])
    }

    @Test("Reports when the device ignores the request")
    func readBackMismatch() async throws {
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            if args.contains("get") {
                return CommandResult(stdout: "deviceOrientation: portrait\ndeviceIsOrientationLocked: false", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "outcome: success", stderr: "", exitCode: 0)
        })

        let response = try await registry.callTool(
            name: "set_orientation",
            arguments: ["udid": .string("AAAA-1111"), "orientation": .string("landscapeRight")]
        )

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.message.contains("still reports portrait"))
    }

    @Test("Reads orientation when none is given")
    func readsOnly() async throws {
        let calls = AllCallCapture()
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            await calls.capture(args)
            return CommandResult(stdout: "deviceOrientation: portrait", stderr: "", exitCode: 0)
        })

        let response = try await registry.callTool(name: "set_orientation", arguments: ["udid": .string("AAAA-1111")])

        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("orientation: portrait"))
        #expect(await calls.allArgs.count == 1)
    }

    @Test("Rejects unknown orientations")
    func rejectsUnknown() async throws {
        let registry = await makeRegistry(executor: .succeedingWith(""))

        let response = try await registry.callTool(
            name: "set_orientation",
            arguments: ["udid": .string("AAAA-1111"), "orientation": .string("sideways")]
        )

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.code == .invalidInput)
    }

    @Test("Parses the orientation line")
    func parses() {
        #expect(parseDeviceOrientation("outcome: success\n  deviceOrientation: landscapeLeft\n") == "landscapeLeft")
        #expect(parseDeviceOrientation("nothing here") == nil)
    }
}

@Suite("record_device_screen")
struct RecordDeviceScreenToolTests {

    private let deviceList = """
    {"result":{"devices":[{"identifier":"DEVICE-UDID","deviceProperties":{"name":"Test iPhone"}}]}}
    """

    @Test("Records for the requested duration")
    func records() async throws {
        let session = SessionStore()
        await session.set(.deviceUDID, value: "DEVICE-UDID")
        let list = deviceList
        let executor = MockCommandExecutor { _, args in
            if args.contains("list") { return CommandResult(stdout: list, stderr: "", exitCode: 0) }
            if args.contains("screen-record"), let i = args.firstIndex(of: "--destination") {
                #expect(args.contains("--duration") && args.contains("5"))
                try Data([0, 0, 0, 0x18]).write(to: URL(fileURLWithPath: args[i + 1]))
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let registry = await makeRegistry(
            executor: executor,
            session: session,
            validator: DefaultsValidator(executor: executor, fileExists: { _ in true })
        )

        let response = try await registry.callTool(name: "record_device_screen", arguments: ["duration": .int(5)])

        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("Recorded 5s from device DEVICE-UDID"))
        #expect(result.artifacts.first?.mimeType == "video/mp4")
    }

    @Test("Rejects durations outside the allowed range")
    func rejectsDuration() async throws {
        let registry = await makeRegistry(executor: .succeedingWith(""))

        let response = try await registry.callTool(name: "record_device_screen", arguments: ["duration": .int(600)])

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.code == .invalidInput)
    }

    @Test("Builds devicectl screen-record arguments")
    func args() {
        #expect(deviceScreenRecordArgs(udid: "U", destination: "/tmp/v.mp4", duration: 7) ==
            ["devicectl", "device", "capture", "screen-record", "--device", "U", "--destination", "/tmp/v.mp4", "--duration", "7"])
    }
}

@Suite("swift_package_test")
struct SwiftPackageTestToolTests {

    @Test("Builds swift test arguments with repetition")
    func arguments() {
        let parsed = SwiftTestOptions.parse([
            "filter": .string("MyTests.testFlaky"),
            "parallel": .bool(true),
            "repeat_until": .string("fail"),
            "maximum_repetitions": .int(25),
        ])
        guard case .success(let options) = parsed else { Issue.record("Expected options"); return }
        #expect(options.arguments(packagePath: "/pkg") == [
            "test", "--package-path", "/pkg", "--filter", "MyTests.testFlaky", "--parallel",
            "--maximum-repetitions", "25", "--repeat-until", "fail",
        ])
    }

    @Test("maximum_repetitions requires repeat_until")
    func repetitionsNeedMode() {
        guard case .failure(let error) = SwiftTestOptions.parse(["maximum_repetitions": .int(5)]) else {
            Issue.record("Expected failure"); return
        }
        #expect(error.code == .invalidInput)
    }

    @Test("Summarizes XCTest and Swift Testing output")
    func summarizes() {
        let output = """
        Test Suite 'All tests' started.
        /pkg/Tests/FooTests.swift:12: error: -[FooTests testBar] : XCTAssertEqual failed: ("1") is not equal to ("2")
        Test Case '-[FooTests testBar]' failed (0.001 seconds).
        Executed 3 tests, with 1 failure (0 unexpected) in 0.003 (0.004) seconds
        ✘ Test parsesInput() failed after 0.002 seconds with 1 issue.
        ✘ Test run with 4 tests in 1 suite failed after 0.010 seconds with 1 issue.
        """
        let summary = summarizeSwiftTestOutput(output)
        #expect(summary.contains("Executed 3 tests, with 1 failure (0 unexpected) in 0.003 (0.004) seconds"))
        #expect(summary.contains { $0.contains("Test run with 4 tests") })
        #expect(summary.contains("Failures (3):"))
    }

    @Test("Runs swift test in the package and reports failure")
    func runsAndFails() async throws {
        let capture = ArgCapture()
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "Executed 1 test, with 1 failure (0 unexpected) in 0.1 (0.1) seconds", stderr: "", exitCode: 1)
        })

        let response = try await registry.callTool(name: "swift_package_test", arguments: ["path": .string("/tmp/pkg")])

        guard case .error(let error) = response else { Issue.record("Expected error"); return }
        #expect(error.message.contains("swift test failed"))
        #expect(await capture.lastArgs == ["test", "--package-path", "/tmp/pkg"])
    }
}

@Suite("debug_task_tree")
struct DebugTaskTreeToolTests {

    @Test("Sends language swift task tree")
    func sendsCommand() async throws {
        let debug = MockDebugSession(
            nextSessionID: "dbg-tasks",
            commandResponses: ["language swift task tree": "Task 0x1 (running)\n  Task 0x2 (suspended)"]
        )
        _ = try await debug.attach(pid: 1, bundleID: nil, udid: nil)
        let registry = await makeRegistry(executor: .succeedingWith(""), debugSession: debug)

        let response = try await registry.callTool(name: "debug_task_tree", arguments: ["session_id": .string("dbg-tasks")])

        guard case .success(let result) = response else { Issue.record("Expected success"); return }
        #expect(result.content.contains("Task 0x2 (suspended)"))
        #expect(await debug.lastCommand == "language swift task tree")
    }
}

@Suite("Xcode 27 options on existing tools")
struct Xcode27OptionTests {

    @Test("Screenshot targets a specific display")
    func screenshotDisplay() {
        #expect(simctlScreenshotArgs(udid: "U", path: "/tmp/s.png", display: "primary-1", mask: "alpha") ==
            ["simctl", "io", "U", "screenshot", "--display=primary-1", "--mask=alpha", "/tmp/s.png"])
        #expect(simctlScreenshotArgs(udid: "U", path: "/tmp/s.png", display: nil, mask: nil) ==
            ["simctl", "io", "U", "screenshot", "/tmp/s.png"])
    }

    @Test("Status bar screenshot preset yields to explicit values")
    func statusBarPreset() async throws {
        let capture = ArgCapture()
        let registry = await makeRegistry(executor: MockCommandExecutor { _, args in
            await capture.capture(args)
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        })

        let response = try await registry.callTool(
            name: "override_status_bar",
            arguments: ["udid": .string("AAAA-1111"), "preset": .string("screenshot"), "time": .string("10:00")]
        )

        guard case .success = response else { Issue.record("Expected success"); return }
        let args = await capture.lastArgs
        #expect(args.contains("--batteryState"))
        #expect(args.filter { $0 == "--time" }.count == 1)
        #expect(args.contains("10:00"))
        #expect(!args.contains("9:41"))
    }

    @Test("test_simulator repetition flags")
    func repetitionFlags() {
        guard case .success(let retry) = xcodebuildTestRepetitionArgs(["retry_on_failure": .bool(true)]) else {
            Issue.record("Expected flags"); return
        }
        #expect(retry == ["-retry-tests-on-failure", "-test-iterations", "3"])

        guard case .success(let until) = xcodebuildTestRepetitionArgs([
            "run_until_failure": .bool(true), "test_iterations": .int(20), "collect_coverage": .bool(true),
        ]) else { Issue.record("Expected flags"); return }
        #expect(until == ["-enableCodeCoverage", "YES", "-run-tests-until-failure", "-test-iterations", "20"])

        guard case .failure = xcodebuildTestRepetitionArgs([
            "run_until_failure": .bool(true), "retry_on_failure": .bool(true),
        ]) else { Issue.record("Expected conflict"); return }
    }
}
