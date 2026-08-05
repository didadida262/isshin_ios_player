import Foundation

struct PlaylistItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var fileURL: URL
    var duration: TimeInterval?

    init(id: UUID = UUID(), title: String, fileURL: URL, duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.duration = duration
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
