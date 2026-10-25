import Foundation

/// Queue metadata for local or provider audio. Signed stream URLs are never persisted here.
struct MusicTrack: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var artist: String
    let filename: String
    let addedAt: Date
    var youtubeID: String? = nil
    var artworkURL: URL? = nil
    var durationSeconds: Double? = nil
    var available: Bool? = nil
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
