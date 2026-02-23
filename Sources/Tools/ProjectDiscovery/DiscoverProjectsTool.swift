//
//  DiscoverProjectsTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

func registerDiscoverProjectsTool(
    with registry: ToolRegistry,
    session: SessionStore
) async {
    let manifest = ToolManifest(
        name: "discover_projects",
        description: "Scan a directory tree for Xcode workspaces (.xcworkspace) and projects (.xcodeproj). Returns structured results sorted with workspaces first. Automatically sets session defaults when a single workspace or project is found.",
        inputSchema: JSONSchema(
            properties: [
                "directory": .init(
                    type: "string",
                    description: "Root directory to scan. Defaults to the current working directory."
                ),
            ]
        ),
        category: .projectDiscovery,
        isReadOnly: true
    )

    await registry.register(manifest: manifest) { args in
        do {
            let directory: String
            if case .string(let dir) = args["directory"] {
                directory = dir
            } else {
                directory = FileManager.default.currentDirectoryPath
            }

            let entries = try scanForProjects(in: directory)

            if entries.isEmpty {
                return .success(ToolResult(
                    content: "No Xcode workspaces or projects found in \(directory)"
                ))
            }

            var lines: [String] = ["Found \(entries.count) Xcode project(s) in \(directory):\n"]

            for entry in entries {
                lines.append("  [\(entry.type)] \(entry.name)")
                lines.append("    Path: \(entry.path)")
            }

            let workspaces = entries.filter { $0.type == .workspace }
            let projects = entries.filter { $0.type == .project }

            if workspaces.count == 1 {
                await session.set(.workspace, value: workspaces[0].path)
                lines.append("\nSession default set: workspace = \(workspaces[0].path)")
            } else if workspaces.isEmpty && projects.count == 1 {
                await session.set(.project, value: projects[0].path)
                lines.append("\nSession default set: project = \(projects[0].path)")
            }

            return .success(ToolResult(content: lines.joined(separator: "\n")))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to scan directory: \(error.localizedDescription)"
            ))
        }
    }
}

// MARK: - Project Scanning

struct ProjectEntry: Sendable {
    enum ProjectType: String, Sendable {
        case workspace
        case project
    }

    let name: String
    let type: ProjectType
    let path: String
}

private let skippedDirectories: Set<String> = [
    ".build", "DerivedData", "Pods", "node_modules", ".git", "Carthage", ".swiftpm",
]

func scanForProjects(in directory: String) throws -> [ProjectEntry] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
        throw ToolError(
            code: .invalidInput,
            message: "Directory does not exist: \(directory)"
        )
    }

    guard let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: directory),
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw ToolError(
            code: .internalError,
            message: "Failed to create directory enumerator for \(directory)"
        )
    }

    var workspaces: [ProjectEntry] = []
    var projects: [ProjectEntry] = []

    while let url = enumerator.nextObject() as? URL {
        let filename = url.lastPathComponent

        if skippedDirectories.contains(filename) {
            enumerator.skipDescendants()
            continue
        }

        if filename.hasSuffix(".xcworkspace") {
            // Skip embedded project.xcworkspace inside .xcodeproj bundles
            if url.deletingLastPathComponent().pathExtension == "xcodeproj" { continue }

            workspaces.append(ProjectEntry(
                name: url.deletingPathExtension().lastPathComponent,
                type: .workspace,
                path: url.path
            ))
            enumerator.skipDescendants()
        } else if filename.hasSuffix(".xcodeproj") {
            projects.append(ProjectEntry(
                name: url.deletingPathExtension().lastPathComponent,
                type: .project,
                path: url.path
            ))
            enumerator.skipDescendants()
        }
    }

    return workspaces + projects
}
