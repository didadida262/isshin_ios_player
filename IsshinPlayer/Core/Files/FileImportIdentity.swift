import Foundation
import UniformTypeIdentifiers

/// Stable identity for matching a browsed file against a sandboxed playlist copy.
///
/// Imports land as `Documents/Imports/<UUID>_<originalName>`. Fingerprints use
/// byte size + original filename so we can mark「已加载」without storing the
/// source path (which evaporates after the security-scoped picker closes).
enum FileImportIdentity {
    private static let uuidPrefixPattern =
        #"^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}_"#

    private static let mediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpeg", "mpg", "3gp",
        "mp3", "m4a", "aac", "wav", "caf", "aiff", "aif", "flac", "ogg", "oga", "opus"
    ]

    static func isMediaFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if mediaExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audiovisualContent) || type.conforms(to: .audio)
    }

    static func fingerprint(forSourceURL url: URL) -> String? {
        guard let size = byteCount(at: url) else { return nil }
        return make(size: size, fileName: url.lastPathComponent)
    }

    /// Fingerprint for a playlist item living under `Documents/Imports`.
    static func fingerprint(forPlaylistFileURL url: URL) -> String? {
        guard let size = byteCount(at: url) else { return nil }
        return make(size: size, fileName: originalFileName(fromImported: url))
    }

    static func originalFileName(fromImported url: URL) -> String {
        let name = url.lastPathComponent
        let stripped = name.replacingOccurrences(
            of: uuidPrefixPattern,
            with: "",
            options: .regularExpression
        )
        return stripped.isEmpty ? name : stripped
    }

    private static func make(size: Int64, fileName: String) -> String {
        "\(size)|\(fileName.lowercased())"
    }

    private static func byteCount(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else { return nil }
        if let size = values?.fileSize { return Int64(size) }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }
}
