// Created by Jared Manfredi

import Darwin
import Foundation
import ImageIO
import MCP

/// Native filenames contain the session key. Consume only this session's files,
/// then delete them; callers publish copies with ordinary ArtifactStore names.
struct NativeUICapture {
    let hierarchy: String
    let screenshot: Data

    init(reply: [String: Value], sessionKey: String,
         artifactRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ActionArtifacts")) throws {
        let root = artifactRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        func ownedURL(_ field: String) -> URL? {
            guard case .string(let path) = reply[field], path.hasPrefix("/"),
                  !sessionKey.isEmpty, !sessionKey.contains("/"), !sessionKey.contains("\0") else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
            guard parent.path.hasPrefix(root), parent.lastPathComponent == "DeviceInteractionSynthesize",
                  url.lastPathComponent.hasPrefix(sessionKey + "-") else { return nil }
            return parent.appendingPathComponent(url.lastPathComponent)
        }
        let fields = ["hierarchyPath", "screenshotPath", "thumbnailScreenshotPath", "logsPath"]
        let files = fields.compactMap(ownedURL)
        defer {
            // Unlinking a file/symlink never follows it or removes a directory.
            for url in files { _ = unlink(url.path) }
        }
        guard let hierarchyURL = ownedURL("hierarchyPath"), let screenshotURL = ownedURL("screenshotPath") else {
            throw Self.invalidCapture()
        }
        let textData = try Self.read(hierarchyURL, limit: 1024 * 1024)
        guard let text = String(data: textData, encoding: .utf8) else { throw Self.invalidCapture() }
        let image = try Self.read(screenshotURL, limit: 20 * 1024 * 1024)
        guard image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(image as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384 else { throw Self.invalidCapture() }
        // Keep the original hierarchy for exact identifier matching; sanitize only
        // at the output boundary so secrets do not change which element is tapped.
        hierarchy = text
        screenshot = image
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw invalidCapture() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size > 0, status.st_size <= limit else { throw invalidCapture() }
        do {
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count == status.st_size, data.count <= limit else { throw invalidCapture() }
            return data
        } catch { throw invalidCapture() }
    }

    private static func invalidCapture() -> ToolError {
        ToolError(code: .commandFailed, message: "Native Xcode returned missing, unsafe, oversized, or unsupported capture files. No native file paths were published.")
    }
}
