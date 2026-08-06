import Foundation

struct PlaylistItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var fileURL: URL
    var duration: TimeInterval?
    /// Photos library local identifier; used to mark already-imported clips in the picker.
    var assetIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        duration: TimeInterval? = nil,
        assetIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.duration = duration
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
    /// Rewind and stay paused on the current item.
    case pauseAtEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单集重播"
        case .pauseAtEnd: return "播完暂停"
        }
    }

    var systemImage: String {
        switch self {
        case .sequential: return "forward.end.alt.fill"
        case .repeatOne: return "repeat.1"
        case .pauseAtEnd: return "stop.circle.fill"
        }
    }

    var next: PlaybackMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
