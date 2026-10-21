// Created by Jared Manfredi

import Foundation
import MCP
import Testing
@testable import Core

private let pilotUDID = "8DF48930-CF63-4ABD-9749-530E74A99366"
private let pilotKey = "private-session-key"
private let pilotTree = """
Device orientation: Unknown
Application bundle identifier: org.iosmcp.NativeUIPilot
Application UI orientation: Portrait
Application, pid: 1, label: 'NativeUIPilot'
 Window, {{0.0, 0.0}, {402.0, 874.0}}, hitPoint: {201.0, 437.0}
  StaticText, {{168.3, 388.5}, {65.3, 20.3}}, identifier: 'pilot.count', label: 'Count: 0', hitPoint: {201.0, 398.7}
  Button, {{162.7, 441.0}, {76.7, 20.3}}, identifier: 'pilot.increment', label: 'Increment', hitPoint: {201.0, 451.2}
"""
private let pilotPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

private struct CaptureFixture: Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var native: URL { root.appendingPathComponent("ActionArtifacts/default/DeviceInteractionSynthesize") }
    var artifactRoot: URL { root.appendingPathComponent("ActionArtifacts") }
    func reply(tree: String = pilotTree) throws -> [String: Value] {
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        var reply: [String: Value] = [:]
        for (key, name, data) in [
            ("hierarchyPath", "hierarchy.txt", Data(tree.utf8)),
            ("screenshotPath", "screenshot.png", pilotPNG),
            ("thumbnailScreenshotPath", "thumbnail.png", pilotPNG),
            ("logsPath", "logs.txt", Data("log".utf8)),
        ] {
            let url = native.appendingPathComponent("\(pilotKey)-\(name)")
            try data.write(to: url)
            reply[key] = .string(url.path)
        }
        return reply
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Native UI hierarchy")
struct NativeUIHierarchyTests {
    @Test func usesNativeHitPoint() throws {
        let hierarchy = try NativeUIHierarchy(text: pilotTree)
        #expect(try hierarchy.point(for: .identifier("pilot.increment")) == CGPoint(x: 201, y: 451.2))
        #expect(try hierarchy.point(for: .label("Increment")) == CGPoint(x: 201, y: 451.2))
        #expect(try hierarchy.point(for: .coordinates(x: 0.5, y: 0.5)) == CGPoint(x: 0.5, y: 0.5))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 402, 1e20])
    func rejectsUnsafeCoordinates(x: Double) throws {
        let hierarchy = try NativeUIHierarchy(text: pilotTree)
        #expect(throws: ToolError.self) { try hierarchy.point(for: .coordinates(x: x, y: 1)) }
    }

    @Test func rejectsMissingAmbiguousAndUnhittableTargets() throws {
        #expect(throws: ToolError.self) { try NativeUIHierarchy(text: pilotTree).point(for: .identifier("absent")) }
        let duplicate = pilotTree + "\n Button, identifier: 'pilot.increment', hitPoint: {20, 20}"
        #expect(throws: ToolError.self) { try NativeUIHierarchy(text: duplicate).point(for: .identifier("pilot.increment")) }
        for suffix in ["", ", hitPoint: {20, 20}, Disabled", ", hitPoint: {20, 20}, activationBundleId: com.other.app"] {
            let text = pilotTree + "\n Button, identifier: 'blocked'" + suffix
            #expect(throws: ToolError.self) { try NativeUIHierarchy(text: text).point(for: .identifier("blocked")) }
        }
    }

    @Test func metadataInsideLabelsCannotCreateTargets() throws {
        let text = pilotTree + #"\n Button, identifier: 'safe', label: 'hello, identifier: \'evil\', hitPoint: {1, 1}', hitPoint: {22, 33}"#.replacingOccurrences(of: #"\n"#, with: "\n")
        let hierarchy = try NativeUIHierarchy(text: text)
        #expect(try hierarchy.point(for: .identifier("safe")) == CGPoint(x: 22, y: 33))
        #expect(throws: ToolError.self) { try hierarchy.point(for: .identifier("evil")) }
        #expect(throws: ToolError.self) { try NativeUIHierarchy(text: "Window, {{nan, 0}, {10, 20}}") }
        #expect(throws: ToolError.self) { try NativeUIHierarchy(text: pilotTree + "\n Button, identifier: 'pilot.increment', label: 'broken") }
        let partial = try NativeUIHierarchy(text: pilotTree + "\n Other, isRemoteLeafPlaceholder")
        #expect(throws: ToolError.self) { try partial.point(for: .identifier("pilot.increment")) }
        let overlapping = try NativeUIHierarchy(text: pilotTree + "\n Button, activationBundleId: com.other.app")
        #expect(throws: ToolError.self) { try overlapping.point(for: .coordinates(x: 1, y: 1)) }
    }
}

@Suite("Native UI capture files")
struct NativeUICaptureTests {
    @Test func consumesOwnedFilesOnly() throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let reply = try fixture.reply()
        let unrelated = fixture.native.appendingPathComponent("other-session-hierarchy.txt")
        try Data("untouched".utf8).write(to: unrelated)
        let capture = try NativeUICapture(reply: reply, sessionKey: pilotKey, artifactRoot: fixture.artifactRoot)
        #expect(capture.hierarchy == pilotTree)
        #expect(capture.screenshot == pilotPNG)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.native.path) == [unrelated.lastPathComponent])
    }

    @Test(arguments: ["outside", "symlink", "oversize", "image", "fifo"])
    func rejectsUnsafeFiles(mode: String) throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        var reply = try fixture.reply()
        let protected = fixture.root.appendingPathComponent("protected.txt")
        try Data("do not read or delete".utf8).write(to: protected)
        guard case .string(let path) = reply["hierarchyPath"] else { return }
        switch mode {
        case "outside": reply["hierarchyPath"] = .string(protected.path)
        case "symlink":
            try FileManager.default.removeItem(atPath: path)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: protected.path)
        case "oversize": try Data(repeating: 65, count: 1024 * 1024 + 1).write(to: URL(fileURLWithPath: path))
        case "fifo":
            try FileManager.default.removeItem(atPath: path)
            #expect(mkfifo(path, 0o600) == 0)
        default:
            guard case .string(let image) = reply["screenshotPath"] else { return }
            try Data("not png".utf8).write(to: URL(fileURLWithPath: image))
        }
        #expect(throws: ToolError.self) { try NativeUICapture(reply: reply, sessionKey: pilotKey, artifactRoot: fixture.artifactRoot) }
        #expect(try String(contentsOf: protected, encoding: .utf8) == "do not read or delete")
    }
}

private actor PilotClient: NativeMCPCalling {
    let fixture: CaptureFixture
    let wrongDevice: Bool
    let failure: String?
    let suspendCapture: Bool
    private(set) var calls: [(String, [String: Value])] = []
    private(set) var closed = false
    init(fixture: CaptureFixture, wrongDevice: Bool = false, failure: String? = nil, suspendCapture: Bool = false) {
        self.fixture = fixture
        self.wrongDevice = wrongDevice
        self.failure = failure
        self.suspendCapture = suspendCapture
    }
    func connect() {}
    func close() { closed = true }
    func call(_ name: String, arguments: [String: Value], timeout: TimeInterval) async throws -> [String: Value] {
        calls.append((name, arguments))
        if failure == name || (failure == "tap" && arguments["interactionCommand"] != nil) {
            throw ToolError(code: .timeout, message: name == "DeviceInteractionStartSession" ? "Native start failed" : "failure including \(pilotKey)")
        }
        switch name {
        case "DeviceInteractionStartSession":
            return ["interactionSessionKey": .string(pilotKey), "deviceIsSimulator": .bool(true),
                    "deviceUUID": .string(wrongDevice ? UUID().uuidString : pilotUDID)]
        case "DeviceInteractionSynthesize":
            if suspendCapture { try await Task.sleep(for: .seconds(60)) }
            let text = pilotTree + "\n Session marker: \(pilotKey)\n Bearer sensitivevalue"
            return try fixture.reply(tree: text)
        default: return [:]
        }
    }
    func waitForCapture() async throws {
        for _ in 0..<1000 {
            if calls.contains(where: { $0.0 == "DeviceInteractionSynthesize" }) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ToolError(code: .timeout, message: "Test capture did not start")
    }
}

@Suite("Native UI lifecycle")
struct NativeUIControllerTests {
    private func controller(_ fixture: CaptureFixture, _ client: PilotClient, _ locks: ConcurrencyPolicy) -> NativeUIController {
        NativeUIController(workspace: "/test/Pilot.xcodeproj", artifacts: ArtifactStore(baseDirectory: fixture.root.appendingPathComponent("managed")),
                           concurrency: locks, artifactRoot: fixture.artifactRoot, makeClient: { client })
    }

    @Test func identifierTapUsesFreshCaptureAndEndsSession() async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let client = PilotClient(fixture: fixture)
        let locks = ConcurrencyPolicy()
        let result = try await controller(fixture, client, locks).tap(udid: pilotUDID, target: .identifier("pilot.increment"))
        let calls = await client.calls
        #expect(calls.map(\.0) == ["XcodeOpenWorkspace", "DeviceInteractionStartSession", "DeviceInteractionSynthesize", "DeviceInteractionSynthesize", "DeviceInteractionEndSession"])
        #expect(calls[3].1["interactionCommand"] == .string("t 201.0 451.2"))
        #expect(!result.content.contains(pilotKey))
        #expect(!result.content.contains("sensitivevalue"))
        #expect(!result.inlineArtifacts)
        #expect(result.artifacts.count == 2)
        for artifact in result.artifacts { #expect(FileManager.default.fileExists(atPath: artifact.path)) }
        #expect(await client.closed)
        #expect(await locks.isLocked(key: "simulator:\(pilotUDID)") == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.native.path).isEmpty)
    }

    @Test func wrongDeviceEndsWithoutTouchingIt() async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let client = PilotClient(fixture: fixture, wrongDevice: true)
        await #expect(throws: ToolError.self) { try await controller(fixture, client, ConcurrencyPolicy()).inspect(udid: pilotUDID) }
        #expect(await client.calls.map(\.0) == ["XcodeOpenWorkspace", "DeviceInteractionStartSession", "DeviceInteractionEndSession"])
        #expect(await client.closed)
    }

    @Test func missingTargetEndsWithoutTap() async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let client = PilotClient(fixture: fixture)
        await #expect(throws: ToolError.self) { try await controller(fixture, client, ConcurrencyPolicy()).tap(udid: pilotUDID, target: .identifier("absent")) }
        let calls = await client.calls
        #expect(!calls.contains(where: { $0.1["interactionCommand"] != nil }))
        #expect(calls.last?.0 == "DeviceInteractionEndSession")
    }

    @Test(arguments: ["tap", "DeviceInteractionEndSession", "DeviceInteractionStartSession"])
    func failuresNeverRetryOrLeakKey(stage: String) async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let client = PilotClient(fixture: fixture, failure: stage)
        do {
            _ = try await controller(fixture, client, ConcurrencyPolicy()).tap(udid: pilotUDID, target: .label("Increment"))
            Issue.record("Expected native failure")
        } catch let error as ToolError {
            #expect(!error.message.contains(pilotKey))
            if stage == "tap" { #expect(error.message.contains("tap may have occurred")) }
            if stage == "DeviceInteractionEndSession" { #expect(error.message.contains("cleanup was not confirmed")) }
            if stage == "DeviceInteractionStartSession" { #expect(error.message.contains("orphaned")) }
        }
        #expect(await client.calls.filter { $0.1["interactionCommand"] != nil }.count <= 1)
        #expect(await client.closed)
    }

    @Test func cancellationAndShutdownAwaitCleanup() async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let client = PilotClient(fixture: fixture, suspendCapture: true)
        let locks = ConcurrencyPolicy()
        let controller = controller(fixture, client, locks)
        let task = Task { try await controller.inspect(udid: pilotUDID) }
        try await client.waitForCapture()
        await #expect(throws: ToolError.self) { try await controller.inspect(udid: pilotUDID) }
        #expect(await locks.isLocked(key: "simulator:\(pilotUDID)"))
        await controller.shutdown()
        await #expect(throws: ToolError.self) { try await task.value }
        #expect(await client.calls.last?.0 == "DeviceInteractionEndSession")
        #expect(await client.closed)
        #expect(await locks.isLocked(key: "simulator:\(pilotUDID)") == false)
    }

    @Test func respectsExistingSimulatorLock() async throws {
        let fixture = CaptureFixture()
        defer { fixture.remove() }
        let locks = ConcurrencyPolicy()
        _ = await locks.acquire(key: "simulator:\(pilotUDID)", owner: "boot")
        let client = PilotClient(fixture: fixture)
        await #expect(throws: ToolError.self) { try await controller(fixture, client, locks).inspect(udid: pilotUDID) }
        #expect(await client.calls.isEmpty)
        #expect(await locks.isLocked(key: "simulator:\(pilotUDID)"))
    }
}
