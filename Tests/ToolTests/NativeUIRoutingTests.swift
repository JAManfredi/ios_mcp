// Created by Jared Manfredi

import Foundation
import MCP
import Testing
@testable import Core
@testable import Tools

private actor RoutingNativeUI: NativeUIAutomating {
    private(set) var targets: [NativeUITarget] = []
    private(set) var udids: [String] = []
    let fail: Bool
    let unavailable: Bool
    let errorCode: ErrorCode
    init(fail: Bool = false, unavailable: Bool = false, errorCode: ErrorCode = .commandDenied) {
        self.fail = fail
        self.unavailable = unavailable
        self.errorCode = errorCode
    }
    func inspect(udid: String) throws -> ToolResult {
        udids.append(udid)
        if unavailable { throw NativeUIUnavailable("auto: native schema unavailable") }
        if fail { throw ToolError(code: errorCode, message: "Native operation failed") }
        return ToolResult(content: "native hierarchy")
    }
    func tap(udid: String, target: NativeUITarget) throws -> ToolResult {
        targets.append(target)
        return try inspect(udid: udid)
    }
}

@Suite("Native UI routing")
struct NativeUIRoutingTests {
    @Test(arguments: [false, true])
    func explicitUnavailabilitySelectsAxeAndReportsReason(axeFails: Bool) async throws {
        let registry = ToolRegistry()
        let native = RoutingNativeUI(unavailable: true)
        let calls = AllCallCapture()
        let executor = MockCommandExecutor { _, args in
            await calls.capture(args)
            return CommandResult(stdout: "axe hierarchy", stderr: "axe failed", exitCode: axeFails ? 1 : 0)
        }
        await registerSnapshotUITool(with: registry, session: SessionStore(), executor: executor, axePath: "/test/axe", validator: testValidator(), nativeUI: native)
        await registerTapTool(with: registry, session: SessionStore(), executor: executor, axePath: "/test/axe", validator: testValidator(), nativeUI: native)
        for name in ["inspect_ui", "tap"] {
            let response = try await registry.callTool(name: name, arguments: ["udid": .string("AAAA-1111"), "accessibility_label": .string("Increment")])
            switch response {
            case .success(let result):
                #expect(!axeFails)
                #expect(result.content.contains("UI backend: axe (auto: native schema unavailable)"))
            case .error(let error):
                #expect(axeFails)
                #expect(error.message.contains("UI backend: axe (auto: native schema unavailable)"))
                #expect(error.code == .commandFailed)
            }
        }
        #expect(await calls.allArgs.map { $0.first } == ["describe-ui", "tap"])
    }

    @Test(arguments: [ErrorCode.dependencyMissing, .timeout, .commandDenied, .invalidInput, .commandFailed])
    func nativeErrorsNeverSelectAxe(code: ErrorCode) async throws {
        let registry = ToolRegistry()
        let native = RoutingNativeUI(fail: true, errorCode: code)
        let executor = MockCommandExecutor { _, _ in
            Issue.record("An error after native selection must not replay through AXe")
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        await registerTapTool(with: registry, session: SessionStore(), executor: executor, validator: testValidator(), nativeUI: native)
        let response = try await registry.callTool(name: "tap", arguments: ["udid": .string("AAAA-1111"), "accessibility_id": .string("primary")])
        guard case .error(let error) = response else { Issue.record("Expected native error"); return }
        #expect(error.code == code)
        #expect(await native.targets.count == 1)
    }

    @Test(arguments: [false, true])
    func optedInToolsNeverExecuteAxe(fail: Bool) async throws {
        let session = SessionStore()
        await session.set(.simulatorUDID, value: "SESSION-UDID")
        let registry = ToolRegistry()
        let native = RoutingNativeUI(fail: fail)
        let executor = MockCommandExecutor { _, _ in
            Issue.record("Native tool unexpectedly invoked AXe")
            return CommandResult(stdout: "", stderr: "", exitCode: 1)
        }
        await registerSnapshotUITool(with: registry, session: session, executor: executor, validator: testValidator(), nativeUI: native)
        await registerTapTool(with: registry, session: session, executor: executor, validator: testValidator(), nativeUI: native)
        for name in ["inspect_ui", "tap"] {
            let response = try await registry.callTool(name: name, arguments: ["accessibility_id": .string("primary"), "x": .double(12), "y": .double(30)])
            switch response {
            case .success(let result): #expect(!fail); #expect(result.content == "native hierarchy")
            case .error(let error): #expect(fail); #expect(error.code == .commandDenied)
            }
        }
        #expect(await native.udids == ["SESSION-UDID", "SESSION-UDID"])
        guard case .identifier("primary") = await native.targets.first else { Issue.record("Expected identifier precedence"); return }
    }

    @Test func nativeCoordinatesPreserveFractionsAndRejectInvalidInputs() async throws {
        let registry = ToolRegistry()
        let native = RoutingNativeUI()
        await registerTapTool(with: registry, session: SessionStore(), executor: MockCommandExecutor.succeedingWith(""), validator: testValidator(), nativeUI: native)
        _ = try await registry.callTool(name: "tap", arguments: ["udid": .string("AAAA-1111"), "x": .double(12.5), "y": .int(30)])
        guard case .coordinates(let x, let y) = await native.targets.first else { Issue.record("Expected coordinates"); return }
        #expect(x == 12.5 && y == 30)
        for value in [Value.double(.nan), .double(.infinity), .double(-1), .string("12")] {
            let response = try await registry.callTool(name: "tap", arguments: ["udid": .string("AAAA-1111"), "x": value, "y": .int(1)])
            guard case .error(let error) = response else { Issue.record("Expected input failure"); continue }
            #expect(error.code == .invalidInput)
        }
        #expect(await native.targets.count == 1)
    }
}
