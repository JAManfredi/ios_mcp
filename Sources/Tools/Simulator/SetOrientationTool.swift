//
//  SetOrientationTool.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Core
import Foundation

/// Orientations `devicectl device orientation set` accepts (UIKit names).
let deviceOrientations = ["portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight"]

func registerSetOrientationTool(
    with registry: ToolRegistry,
    session: SessionStore,
    executor: any CommandExecuting,
    validator: DefaultsValidator
) async {
    let manifest = ToolManifest(
        name: "set_orientation",
        description: "Rotate a booted simulator, or read its current orientation when `orientation` is omitted. Uses `devicectl device orientation` (Xcode 27+); simctl has no rotation command. Falls back to session default simulator_udid.",
        inputSchema: JSONSchema(
            properties: [
                "udid": .init(
                    type: "string",
                    description: "Simulator UDID. Falls back to session default."
                ),
                "orientation": .init(
                    type: "string",
                    description: "Target orientation. Omit to read the current one.",
                    enumValues: deviceOrientations
                ),
            ]
        ),
        category: .simulator
    )

    await registry.register(manifest: manifest) { args in
        let resolvedUDID: String
        switch await resolveSimulatorUDID(from: args, session: session, validator: validator) {
        case .success(let udid): resolvedUDID = udid
        case .failure(let error): return .error(error)
        }

        var target: String?
        if case .string(let requested) = args["orientation"] {
            guard deviceOrientations.contains(requested) else {
                return .error(ToolError(
                    code: .invalidInput,
                    message: "orientation must be one of: \(deviceOrientations.joined(separator: ", "))."
                ))
            }
            target = requested
        }

        do {
            if let target {
                let setResult = try await executor.execute(
                    executable: "/usr/bin/xcrun",
                    arguments: ["devicectl", "device", "orientation", "set", "--device", resolvedUDID, target],
                    timeout: 30,
                    environment: nil
                )
                guard setResult.succeeded else {
                    return .error(orientationError("set", stderr: setResult.stderr))
                }
            }

            // Read back even after a set: devicectl can report success while the
            // device stays put (seen on the iPhone Duo under Xcode 27.1).
            let getResult = try await executor.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["devicectl", "device", "orientation", "get", "--device", resolvedUDID],
                timeout: 30,
                environment: nil
            )
            guard getResult.succeeded else {
                if let target {
                    return .success(ToolResult(
                        content: "Requested \(target) on simulator \(resolvedUDID); read-back failed, so take a screenshot to confirm."
                    ))
                }
                return .error(orientationError("get", stderr: getResult.stderr))
            }

            let current = parseDeviceOrientation(getResult.stdout)
            let locked = getResult.stdout.contains("deviceIsOrientationLocked: true")

            guard let target else {
                var content = "Simulator \(resolvedUDID) orientation: \(current ?? "unknown")"
                if locked { content += " (orientation locked)" }
                return .success(ToolResult(content: content))
            }

            if let current, current != target {
                var content = "devicectl accepted \(target), but simulator \(resolvedUDID) still reports \(current)."
                if locked { content += " Orientation lock is on." }
                content += " The app may not support \(target), or the device ignored the request."
                return .error(ToolError(code: .commandFailed, message: content, details: getResult.stdout))
            }

            return .success(ToolResult(content: "Simulator \(resolvedUDID) rotated to \(target)."))
        } catch let error as ToolError {
            return .error(error)
        } catch {
            return .error(ToolError(
                code: .internalError,
                message: "Failed to change orientation: \(error.localizedDescription)"
            ))
        }
    }
}

/// Pulls the value out of the `deviceOrientation: landscapeLeft` line.
func parseDeviceOrientation(_ output: String) -> String? {
    for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("deviceOrientation:") else { continue }
        let value = trimmed.dropFirst("deviceOrientation:".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    return nil
}

private func orientationError(_ verb: String, stderr: String) -> ToolError {
    let unknown = stderr.contains("Unknown") || stderr.contains("unrecognized") || stderr.contains("not a valid")
    return ToolError(
        code: unknown ? .dependencyMissing : .commandFailed,
        message: unknown
            ? "`devicectl device orientation` needs Xcode 27 or later."
            : "devicectl orientation \(verb) failed. The simulator must be booted.",
        details: stderr
    )
}
