//
//  AxeHealth.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation

/// Oldest axe that supports the simulators this server targets. Below this,
/// UI automation fails against newer runtimes in ways that surface as unrelated
/// tool errors rather than as a version problem.
public let minimumAxeVersion = "1.8.0"

/// Explains why `axe --version` didn't run.
///
/// The cause that isn't self-evident is architecture. Releases before 1.8.0
/// were arm64-only, so on an Intel host axe fails with "bad CPU type in
/// executable" and every UI automation tool then dies at call time with nothing
/// pointing at the reason. 1.8.0 onward ships a universal binary, so upgrading
/// is the fix rather than a dead end.
public func axeFailureDetail(binaryPath: String, failure: String = "") -> String {
    let generic = "found at \(binaryPath) but --version failed"
    let host = hostArchitecture()
    let executable = resolveWrappedExecutable(at: binaryPath)
    let architectures = machOArchitectures(at: executable)

    // The launcher's own complaint is the most reliable signal — it survives a
    // wrapper we couldn't follow, or a header we couldn't parse.
    let refusedToLaunch = failure.range(of: "bad cpu type", options: .caseInsensitive) != nil

    if let architectures, architectures.contains(host) { return generic }
    guard refusedToLaunch || architectures != nil else { return generic }

    let describes = architectures.map { "is \($0.joined(separator: "/"))-only" }
        ?? "cannot run"
    return """
        \(executable) \(describes) and this host is \(host), \
        so UI automation tools are unavailable. \
        axe \(minimumAxeVersion) ships a universal binary — run: \
        brew upgrade cameroncooke/axe/axe
        """
}

/// Warning when the installed axe predates `minimumAxeVersion`.
public func axeVersionWarning(reported: String) -> String? {
    guard let found = firstSemanticVersion(in: reported) else { return nil }
    guard isVersion(found, olderThan: minimumAxeVersion) else { return nil }
    return "older than \(minimumAxeVersion); newer simulators may not be supported. "
        + "Run: brew upgrade cameroncooke/axe/axe"
}

/// Pulls `1.4.0` out of whatever shape `--version` prints.
public func firstSemanticVersion(in text: String) -> String? {
    let pattern = /[0-9]+\.[0-9]+(\.[0-9]+)?/
    return text.firstMatch(of: pattern).map { String($0.output.0) }
}

public func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b { return a < b }
    }
    return false
}

public func hostArchitecture() -> String {
    var info = utsname()
    uname(&info)
    let machine = withUnsafeBytes(of: &info.machine) { raw in
        raw.prefix(while: { $0 != 0 }).map { CChar($0) }
    }
    return String(cString: machine + [0])
}

/// Architectures in a Mach-O file, read from its header rather than by shelling
/// out — this runs during startup diagnostics and shouldn't spawn processes.
///
/// Fat binaries are expanded to their actual slices. Returning a placeholder
/// like `["universal"]` would fail a host-architecture membership test and make
/// a perfectly runnable binary look incompatible.
public func machOArchitectures(at path: String) -> [String]? {
    guard let handle = FileHandle(forReadingAtPath: path),
          let head = try? handle.read(upToCount: 4096), head.count >= 8 else { return nil }
    defer { try? handle.close() }

    let bytes = [UInt8](head)

    func word(_ offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        let value = bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }

    guard let magic = word(0, bigEndian: true) else { return nil }

    // Fat header: magic, count, then one entry per slice naming its CPU type.
    if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
        let is64 = magic == 0xCAFE_BABF
        let entrySize = is64 ? 32 : 20
        guard let count = word(4, bigEndian: true), count < 32 else { return nil }

        var architectures: [String] = []
        for index in 0..<Int(count) {
            let offset = 8 + index * entrySize
            guard let cpuType = word(offset, bigEndian: true) else { break }
            if let name = architectureName(cpuType) { architectures.append(name) }
        }
        return architectures.isEmpty ? nil : architectures
    }

    let isMachO = [0xFEED_FACF, 0xCFFA_EDFE, 0xFEED_FACE, 0xCEFA_EDFE].contains(Int(magic))
    guard isMachO else { return nil }

    let littleEndian = magic == 0xCFFA_EDFE || magic == 0xCEFA_EDFE
    guard let cpuType = word(4, bigEndian: !littleEndian),
          let name = architectureName(cpuType) else { return nil }
    return [name]
}

private func architectureName(_ cpuType: UInt32) -> String? {
    switch cpuType & 0x00FF_FFFF {
    case 7: return "x86_64"
    case 12: return "arm64"
    default: return nil
    }
}

/// Follows a shell wrapper to the executable it runs.
///
/// Homebrew installs axe as a Bash script that `exec`s a binary under
/// `libexec`, so inspecting the path returned by `which` reads the wrapper and
/// learns nothing about the architecture that actually has to run.
public func resolveWrappedExecutable(at path: String) -> String {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
          contents.hasPrefix("#!") else { return path }

    let pattern = /exec\s+"?([^"\s]+)"?/
    guard let match = contents.firstMatch(of: pattern) else { return path }

    let target = String(match.output.1)
    return FileManager.default.isExecutableFile(atPath: target) ? target : path
}

