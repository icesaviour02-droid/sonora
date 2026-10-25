import Foundation
import SwiftUI

/// Queue and catalog metadata for local or provider audio. Signed stream URLs are never persisted here.
struct MusicTrack: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var artist: String
    let filename: String
    let addedAt: Date
    var youtubeID: String? = nil
    var artistID: String? = nil
    var albumTitle: String? = nil
    var albumID: String? = nil
    var artworkURL: URL? = nil
    var durationSeconds: Double? = nil
    var explicit: Bool = false
    var available: Bool? = nil
    var liked: Bool? = nil
    var setVideoID: String? = nil
}

/// Album summary returned by YouTube Music search, home shelves, artist pages, and library.
struct CatalogAlbum: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artistID: String?
    let year: UInt16?
    let artworkURL: URL?
    var explicit: Bool = false
}

/// Artist summary returned by YouTube Music search, home shelves, and library.
struct CatalogArtist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
}

/// Playlist summary returned by YouTube Music search, home shelves, and library.
struct CatalogPlaylist: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let trackCount: Int?
    let artworkURL: URL?
    var editable: Bool = false
}

/// Genre or mood category tile from YouTube Music explore.
struct GenreCategory: Codable, Identifiable, Hashable {
    var id: String { params }
    let title: String
    let params: String
    let color: UInt32
}

/// Single card in a Home or Genre horizontal shelf.
struct HomeShelfItem: Identifiable, Hashable {
    let id: String
    let kind: String
    let targetID: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let track: MusicTrack?
    let album: CatalogAlbum?
    let playlist: CatalogPlaylist?
    let artist: CatalogArtist?
}

/// Named horizontal shelf on the Home or Genre screen.
struct HomeShelfSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [HomeShelfItem]
}

/// User-pinned item shown at the top of Home and in the Library Pinned collection.
struct PinnedItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable { case track, album, playlist, artist }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let targetID: String
    let track: MusicTrack?
}

/// Time-synced or static lyrics line returned by the Rust mobile core (LRCLIB / YouTube Music).
struct LyricsLineItem: Codable, Identifiable, Hashable {
    let id: Int
    let text: String
    let romanized: String?
    let start_seconds: Double?
    let end_seconds: Double?
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

/// Audio quality ceilings matching Sonora's desktop streaming and download settings.
enum AudioQuality: String, CaseIterable, Codable, Identifiable {
    case high, normal, low
    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .high: "ios-quality-high"
        case .normal: "ios-quality-normal"
        case .low: "ios-quality-low"
        }
    }
}

/// Equalizer presets matching Sonora's desktop equalizer profiles.
enum EqualizerPreset: String, CaseIterable, Codable, Identifiable {
    case flat, bassBoost, bassReducer, trebleBoost, vocal, rock, pop, jazz, classical, electronic, acoustic, loudness, custom
    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .flat: "ios-eq-flat"
        case .bassBoost: "ios-eq-bass-boost"
        case .bassReducer: "ios-eq-bass-reducer"
        case .trebleBoost: "ios-eq-treble-boost"
        case .vocal: "ios-eq-vocal"
        case .rock: "ios-eq-rock"
        case .pop: "ios-eq-pop"
        case .jazz: "ios-eq-jazz"
        case .classical: "ios-eq-classical"
        case .electronic: "ios-eq-electronic"
        case .acoustic: "ios-eq-acoustic"
        case .loudness: "ios-eq-loudness"
        case .custom: "ios-eq-custom"
        }
    }

    var preampDB: Double {
        switch self {
        case .flat, .custom: 0
        case .bassBoost, .trebleBoost, .rock, .electronic, .loudness: -2.0
        case .pop, .vocal, .jazz, .acoustic: -1.0
        case .bassReducer, .classical: 0
        }
    }

    var bassDB: Double {
        switch self {
        case .flat, .custom, .trebleBoost, .classical: 0
        case .bassBoost: 5.5
        case .bassReducer: -5.0
        case .vocal: -1.5
        case .rock: 4.0
        case .pop: 2.5
        case .jazz: 2.0
        case .electronic: 4.5
        case .acoustic: 2.0
        case .loudness: 4.5
        }
    }

    var trebleDB: Double {
        switch self {
        case .flat, .custom, .bassBoost, .bassReducer: 0
        case .trebleBoost: 5.5
        case .vocal: 2.5
        case .rock: 3.5
        case .pop: 2.5
        case .jazz: 1.5
        case .classical: 2.0
        case .electronic: 3.5
        case .acoustic: 2.5
        case .loudness: 3.5
        }
    }
}

/// Sleep timer intervals matching Sonora's desktop sleep timer.
enum SleepTimerOption: String, CaseIterable, Codable, Identifiable {
    case off, fifteen, thirty, fortyFive, sixty, endOfTrack
    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .off: "ios-sleep-off"
        case .fifteen: "ios-sleep-15"
        case .thirty: "ios-sleep-30"
        case .fortyFive: "ios-sleep-45"
        case .sixty: "ios-sleep-60"
        case .endOfTrack: "ios-sleep-end-of-track"
        }
    }

    var minutes: Int? {
        switch self {
        case .off, .endOfTrack: nil
        case .fifteen: 15
        case .thirty: 30
        case .fortyFive: 45
        case .sixty: 60
        }
    }
}

/// Appearance theme selection matching Sonora's desktop theme setting.
enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .system: "ios-theme-system"
        case .light: "ios-theme-light"
        case .dark: "ios-theme-dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// One set of layout metrics shared by the native Apple Music-style surfaces.
enum Layout {
    static let playerMargin: CGFloat = 24
    static let playerSpacing: CGFloat = 12
    static let playerChrome: CGFloat = 410
    static let playerMinimumArtwork: CGFloat = 140
    static let accessibleArtwork: CGFloat = 200
    static let artworkRadius: CGFloat = 12
    static let spacing: CGFloat = 16
    static let compact: CGFloat = 8
    static let control: CGFloat = 44
    static let artwork: CGFloat = 296
    static let detailArtwork: CGFloat = 220
    static let cardArtwork: CGFloat = 152
    static let cardRadius: CGFloat = 12
    static let rowArtwork: CGFloat = 48
    static let miniArtwork: CGFloat = 40
}

/// Requests a retina-sized rendition only from the provider's known resizable artwork hosts.
enum ArtworkRendition {
    static func url(_ original: URL?, side: CGFloat) -> URL? {
        guard let original, let host = original.host,
              host.hasSuffix(".googleusercontent.com") || host.hasSuffix(".ggpht.com") else { return original }
        let pixels = Int(ceil(max(1, side) * 3))
        let value = original.absoluteString.replacingOccurrences(
            of: "=w[0-9]+-h[0-9]+", with: "=w\(pixels)-h\(pixels)", options: .regularExpression)
        return URL(string: value) ?? original
    }
}
