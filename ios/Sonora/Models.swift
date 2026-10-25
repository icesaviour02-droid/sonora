import Foundation

/// A sandbox-owned audio file. Relative paths survive changes to the app container after updates.
struct LocalTrack: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var artist: String
    let filename: String
    let addedAt: Date
}

/// Playback repeat behavior, stored with the queue rather than with a screen.
enum RepeatMode: String, Codable {
    case off, all, one

    var next: Self {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// One set of layout metrics shared by the native surfaces.
enum Layout {
    static let spacing: CGFloat = 16
    static let compact: CGFloat = 8
    static let control: CGFloat = 44
    static let artwork: CGFloat = 260
}
