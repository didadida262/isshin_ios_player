import Foundation
import UniformTypeIdentifiers

enum MediaKind: String, Codable, Equatable, Hashable {
    case video
    case audio

    static func infer(from url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        let audioExtensions: Set<String> = [
            "mp3", "m4a", "aac", "wav", "caf", "aiff", "aif", "flac", "ogg", "oga", "opus"
        ]
        if audioExtensions.contains(ext) { return .audio }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .audio) {
            return .audio
        }
        return .video
    }

    var listSystemImage: String {
        switch self {
        case .video: return "video"
        case .audio: return "music.note"
        }
    }

    var listSystemImageFilled: String {
        switch self {
        case .video: return "video.fill"
        case .audio: return "music.note"
        }
    }
}

struct PlaylistItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var fileURL: URL
    var duration: TimeInterval?
    var mediaKind: MediaKind
    /// Photos library local identifier; used to mark already-imported clips in the picker.
    var assetIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        duration: TimeInterval? = nil,
        mediaKind: MediaKind? = nil,
        assetIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.duration = duration
        self.mediaKind = mediaKind ?? .infer(from: fileURL)
        self.assetIdentifier = assetIdentifier
    }
}

enum PlayerPhase: Equatable {
    case empty
    case loading
    case ready
    case error(String)
}

enum PlaybackRate: Float, CaseIterable, Identifiable {
    case x0_5 = 0.5
    case x0_75 = 0.75
    case x1 = 1.0
    case x1_25 = 1.25
    case x1_5 = 1.5
    case x2 = 2.0

    var id: Float { rawValue }

    var label: String {
        switch self {
        case .x0_5: return "0.5x"
        case .x0_75: return "0.75x"
        case .x1: return "1x"
        case .x1_25: return "1.25x"
        case .x1_5: return "1.5x"
        case .x2: return "2x"
        }
    }
}

/// What happens when the current video finishes.
enum PlaybackMode: String, CaseIterable, Identifiable {
    /// Play the next item; stop (rewound) if this is the last.
    case sequential
    /// Restart the current item automatically.
    case repeatOne

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单集循环"
        }
    }

    /// Thin-line SF Symbols in the NetEase-style loop family.
    var systemImage: String {
        switch self {
        case .sequential: return "repeat"      // list loop
        case .repeatOne: return "repeat.1"     // single loop
        }
    }

    var next: PlaybackMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
