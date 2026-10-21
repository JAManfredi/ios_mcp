import Core
import Foundation
import MCP
import Testing
@testable import Tools

@Suite("Device capture cleanup")
struct DeviceCaptureCleanupTests {
    @Test(arguments: ["device_screenshot", "record_device_screen"], ["success", "command", "timeout", "cancel", "empty", "storage"])
    func removesTemporaryCapture(tool: String, outcome: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let managed = root.appendingPathComponent("managed")
        if outcome == "storage" { try Data().write(to: managed) }
        let capture = ArgCapture()
        let executor = MockCommandExecutor { _, args in
            guard let index = args.firstIndex(of: "--destination") else {
                return CommandResult(stdout: #"{"result":{"devices":[{"identifier":"DEVICE-ID","deviceProperties":{"name":"Phone"}}]}}"#, stderr: "", exitCode: 0)
            }
            await capture.capture(args)
            try (outcome == "empty" ? Data() : Data([1, 2, 3])).write(to: URL(fileURLWithPath: args[index + 1]))
            if outcome == "timeout" { throw ToolError(code: .timeout, message: "Capture timed out") }
            if outcome == "cancel" { throw CancellationError() }
            return CommandResult(stdout: "", stderr: "Capture failed", exitCode: outcome == "command" ? 1 : 0)
        }
        let registry = ToolRegistry()
        let session = SessionStore()
        let validator = DefaultsValidator(executor: executor)
        let artifacts = ArtifactStore(baseDirectory: managed)
        await registerDeviceScreenshotTool(with: registry, session: session, executor: executor, artifacts: artifacts, validator: validator)
        await registerRecordDeviceScreenTool(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: artifacts, validator: validator)
        let response = try await registry.callTool(name: tool, arguments: ["device_udid": .string("DEVICE-ID")])
        let args = await capture.lastArgs
        let index = try #require(args.firstIndex(of: "--destination"))
        #expect(!FileManager.default.fileExists(atPath: args[index + 1]))
        if case .success(let result) = response {
            #expect(outcome == "success")
            let artifact = try #require(result.artifacts.first)
            #expect(try Data(contentsOf: URL(fileURLWithPath: artifact.path)) == Data([1, 2, 3]))
        } else {
            #expect(outcome != "success")
            if outcome == "timeout", case .error(let error) = response { #expect(error.code == .timeout) }
        }
    }
}
