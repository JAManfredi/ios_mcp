//
//  DiscoverProjectsToolTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core
@testable import Tools

@Suite("discover_projects")
struct DiscoverProjectsToolTests {
    private func createTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func createDir(at base: URL, name: String) throws {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Happy Path

    @Test("Finds workspace and project")
    func findsWorkspaceAndProject() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "MyApp.xcworkspace")
        try createDir(at: tmp, name: "MyApp.xcodeproj")

        let entries = try scanForProjects(in: tmp.path)

        #expect(entries.count == 2)
        #expect(entries[0].type == .workspace)
        #expect(entries[0].name == "MyApp")
        #expect(entries[1].type == .project)
        #expect(entries[1].name == "MyApp")
    }

    @Test("Workspaces listed before projects")
    func workspacesFirst() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "Alpha.xcodeproj")
        try createDir(at: tmp, name: "Beta.xcworkspace")

        let entries = try scanForProjects(in: tmp.path)

        #expect(entries.count == 2)
        #expect(entries[0].type == .workspace)
        #expect(entries[1].type == .project)
    }

    // MARK: - Skipped Directories

    @Test("Skips DerivedData, .build, Pods, etc.")
    func skipsExcludedDirectories() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "DerivedData/Hidden.xcodeproj")
        try createDir(at: tmp, name: ".build/Hidden.xcodeproj")
        try createDir(at: tmp, name: "Pods/Hidden.xcodeproj")
        try createDir(at: tmp, name: "Visible.xcodeproj")

        let entries = try scanForProjects(in: tmp.path)

        #expect(entries.count == 1)
        #expect(entries[0].name == "Visible")
    }

    // MARK: - Embedded Workspaces

    @Test("Filters embedded project.xcworkspace inside .xcodeproj")
    func filtersEmbeddedWorkspace() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "MyApp.xcodeproj/project.xcworkspace")

        let entries = try scanForProjects(in: tmp.path)

        #expect(entries.count == 1)
        #expect(entries[0].type == .project)
        #expect(entries[0].name == "MyApp")
    }

    // MARK: - Empty Directory

    @Test("Returns empty for directory with no projects")
    func emptyDirectory() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        let entries = try scanForProjects(in: tmp.path)

        #expect(entries.isEmpty)
    }

    // MARK: - Invalid Directory

    @Test("Throws for nonexistent directory")
    func invalidDirectory() async {
        do {
            _ = try scanForProjects(in: "/nonexistent/path/\(UUID().uuidString)")
            Issue.record("Expected ToolError to be thrown")
        } catch let error as ToolError {
            #expect(error.code == .invalidInput)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Session Auto-Set

    @Test("Sets session workspace when exactly one workspace found")
    func sessionAutoSetWorkspace() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "Solo.xcworkspace")
        try createDir(at: tmp, name: "Other.xcodeproj")

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "discover_projects",
            arguments: ["directory": .string(tmp.path)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: workspace"))
        } else {
            Issue.record("Expected success response")
        }

        let ws = await session.get(.workspace)
        #expect(ws != nil)
        #expect(ws!.contains("Solo.xcworkspace"))
    }

    @Test("Sets session project when no workspaces and exactly one project found")
    func sessionAutoSetProject() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "Solo.xcodeproj")

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "discover_projects",
            arguments: ["directory": .string(tmp.path)]
        )

        if case .success(let result) = response {
            #expect(result.content.contains("Session default set: project"))
        } else {
            Issue.record("Expected success response")
        }

        let proj = await session.get(.project)
        #expect(proj != nil)
        #expect(proj!.contains("Solo.xcodeproj"))
    }

    @Test("No auto-set when multiple projects found")
    func noAutoSetMultipleProjects() async throws {
        let tmp = try createTempDir()
        defer { cleanup(tmp) }

        try createDir(at: tmp, name: "AppA.xcodeproj")
        try createDir(at: tmp, name: "AppB.xcodeproj")

        let session = SessionStore()
        let registry = ToolRegistry()
        let executor = MockCommandExecutor.succeedingWith("")

        await registerAllTools(with: registry, session: session, executor: executor, concurrency: ConcurrencyPolicy(), artifacts: ArtifactStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())), logCapture: MockLogCapture(), debugSession: MockDebugSession(), validator: testValidator())

        let response = try await registry.callTool(
            name: "discover_projects",
            arguments: ["directory": .string(tmp.path)]
        )

        if case .success(let result) = response {
            #expect(!result.content.contains("Session default set"))
        } else {
            Issue.record("Expected success response")
        }

        let proj = await session.get(.project)
        #expect(proj == nil)
    }
}
