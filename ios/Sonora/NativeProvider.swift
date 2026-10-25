import Foundation
import Observation

/// Stable errors cross the native boundary; raw provider responses and signed URLs never reach alerts.
enum ProviderError: LocalizedError {
    case unavailable, timeout, signInRequired

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "ios-provider-error")
        case .timeout: String(localized: "ios-provider-timeout")
        case .signInRequired: String(localized: "ios-provider-sign-in-required")
        }
    }
}

/// Native response ownership lasts through cancellation until the bounded Rust callback arrives.
private final class NativeReply {
    let continuation: CheckedContinuation<Data, Error>
    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
}

private func receiveNativeReply(_ context: UnsafeMutableRawPointer?, _ json: UnsafeMutablePointer<CChar>?) {
    guard let context else { if let json { sonora_mobile_string_free(json) }; return }
    let reply = Unmanaged<NativeReply>.fromOpaque(context).takeRetainedValue()
    guard let json else { reply.continuation.resume(throwing: ProviderError.unavailable); return }
    let data = Data(bytes: json, count: strlen(json))
    sonora_mobile_string_free(json)
    reply.continuation.resume(returning: data)
}

/// Thin asynchronous adapter. All provider sockets and stream resolution run in the Rust core.
enum NativeProvider {
    private struct Envelope<Value: Decodable>: Decodable {
        let ok: Bool
        let data: Value?
        let error: String?
    }

    struct Song: Decodable {
        let id: String
        let title: String
        let artist: String
        let artist_id: String?
        let album_title: String?
        let album_id: String?
        let artwork_url: URL?
        let duration_seconds: Double?
        let explicit: Bool?
        let available: Bool
        let liked: Bool?
        let set_video_id: String?

        var track: MusicTrack {
            MusicTrack(
                id: "youtube:" + id,
                title: title,
                artist: artist,
                filename: "",
                addedAt: .now,
                youtubeID: id,
                artistID: artist_id,
                albumTitle: album_title,
                albumID: album_id,
                artworkURL: artwork_url,
                durationSeconds: duration_seconds,
                explicit: explicit ?? false,
                available: available,
                liked: liked,
                setVideoID: set_video_id
            )
        }
    }

    struct AlbumPayload: Decodable {
        let id: String
        let title: String
        let artist: String
        let artist_id: String?
        let year: UInt16?
        let artwork_url: URL?
        let explicit: Bool?

        var album: CatalogAlbum {
            CatalogAlbum(
                id: id,
                title: title,
                artist: artist,
                artistID: artist_id,
                year: year,
                artworkURL: artwork_url,
                explicit: explicit ?? false
            )
        }
    }

    struct ArtistPayload: Decodable {
        let id: String
        let name: String
        let artwork_url: URL?

        var artist: CatalogArtist {
            CatalogArtist(id: id, name: name, artworkURL: artwork_url)
        }
    }

    struct PlaylistPayload: Decodable {
        let id: String
        let title: String
        let author: String
        let track_count: Int?
        let artwork_url: URL?
        let editable: Bool?

        var playlist: CatalogPlaylist {
            CatalogPlaylist(
                id: id,
                title: title,
                author: author,
                trackCount: track_count,
                artworkURL: artwork_url,
                editable: editable ?? false
            )
        }
    }

    struct GenrePayload: Decodable {
        let title: String
        let params: String
        let color: UInt32

        var genre: GenreCategory {
            GenreCategory(title: title, params: params, color: color)
        }
    }

    struct HomeItemPayload: Decodable {
        let kind: String
        let id: String
        let title: String
        let subtitle: String
        let artwork_url: URL?
        let song: Song?
        let album: AlbumPayload?
        let playlist: PlaylistPayload?
        let artist: ArtistPayload?

        var item: HomeShelfItem {
            HomeShelfItem(
                id: kind + ":" + id + ":" + title,
                kind: kind,
                targetID: id,
                title: title,
                subtitle: subtitle,
                artworkURL: artwork_url,
                track: song?.track,
                album: album?.album,
                playlist: playlist?.playlist,
                artist: artist?.artist
            )
        }
    }

    struct HomeSectionPayload: Decodable {
        let title: String
        let items: [HomeItemPayload]

        var section: HomeShelfSection {
            HomeShelfSection(id: title, title: title, items: items.map(\.item))
        }
    }

    struct HomePayload: Decodable {
        let sections: [HomeSectionPayload]
        let genres: [GenrePayload]
    }

    struct CatalogSearchPayload: Decodable {
        let songs: [Song]
        let albums: [AlbumPayload]
        let playlists: [PlaylistPayload]
        let artists: [ArtistPayload]
    }

    struct AlbumDetailPayload: Decodable {
        let id: String
        let title: String
        let artist: String
        let artist_id: String?
        let year: UInt16?
        let artwork_url: URL?
        let tracks: [Song]
    }

    struct ArtistDetailPayload: Decodable {
        let id: String
        let name: String
        let description: String?
        let subscribers: String?
        let artwork_url: URL?
        let subscribed: Bool?
        let top_songs: [Song]
        let albums: [AlbumPayload]
        let singles: [AlbumPayload]
        let related: [ArtistPayload]
    }

    struct PlaylistDetailPayload: Decodable {
        let id: String
        let title: String
        let author: String
        let description: String?
        let track_count: Int?
        let artwork_url: URL?
        let editable: Bool
        let privacy: String?
        let liked: Bool?
        let tracks: [Song]
    }

    struct LibraryContentPayload: Decodable {
        let liked_songs: [Song]
        let albums: [AlbumPayload]
        let playlists: [PlaylistPayload]
        let artists: [ArtistPayload]
    }

    struct Stream: Decodable {
        let url: URL
        let mime: String
        let codec: String?
        let bitrate_kbps: UInt32?
        let loudness_db: Float?
        let user_agent: String
        let duration_seconds: Double?
        let content_length: UInt64?
    }

    struct Lyrics: Decodable {
        let text: String?
        let lines: [LyricsLineItem]?
        let synced: Bool?
        let instrumental: Bool?
        let source: String
    }

    struct Account: Decodable, Identifiable, Hashable {
        let name: String
        let handle: String?
        let avatar_url: String?
        let authuser: UInt8?
        let page_id: String?

        var id: String { "\(authuser ?? 0):\(page_id ?? ""):\(name)" }
    }

    private struct Status: Decodable {}
    private struct SignedOut: Decodable { let signed_out: Bool }
    private struct PoTokenWanted: Decodable { let binding: String? }
    private struct CreatedPlaylist: Decodable { let playlist_id: String }

    static func configure(cacheDir: String) async {
        let _: Status? = try? await request(["operation": "configure", "cache_dir": cacheDir])
    }

    static func poTokenWanted() async -> String? {
        let result: PoTokenWanted? = try? await request(["operation": "po_token_wanted"])
        return result?.binding
    }

    static func poTokenGive(binding: String, token: String) async {
        let _: Status? = try? await request(["operation": "po_token_give", "binding": binding, "token": token])
    }

    static func poTokenFailed() async {
        let _: Status? = try? await request(["operation": "po_token_failed"])
    }

    static func listAccounts(_ cookies: String) async throws -> [Account] {
        try await request(["operation": "list_accounts", "cookies": cookies])
    }

    static func authenticate(_ cookies: String, authuser: UInt8 = 0, pageID: String? = nil) async throws -> Account {
        var payload: [String: Any] = ["operation": "authenticate", "cookies": cookies, "authuser": Int(authuser)]
        if let pageID, !pageID.isEmpty { payload["page_id"] = pageID }
        return try await request(payload)
    }

    static func rotateCookies() async {
        let _: Status? = try? await request(["operation": "rotate_cookies"])
    }

    static func signOut() async throws {
        let _: SignedOut = try await request(["operation": "sign_out"])
    }

    static func search(_ query: String) async throws -> [MusicTrack] {
        let songs: [Song] = try await request(["operation": "search", "query": query])
        var seen: Set<String> = []
        return songs.map(\.track).filter { seen.insert($0.id).inserted }
    }

    static func searchCatalog(_ query: String) async throws -> CatalogSearchPayload {
        try await request(["operation": "search_catalog", "query": query])
    }

    static func searchSuggestions(_ input: String) async throws -> [String] {
        try await request(["operation": "search_suggestions", "input": input])
    }

    static func resolve(_ id: String, quality: AudioQuality = .high) async throws -> Stream {
        try await request(["operation": "resolve", "video_id": id, "quality": quality.rawValue])
    }

    static func lyrics(_ id: String, title: String? = nil, artist: String? = nil) async throws -> Lyrics {
        var payload: [String: Any] = ["operation": "lyrics", "video_id": id]
        if let title, !title.isEmpty { payload["title"] = title }
        if let artist, !artist.isEmpty { payload["artist"] = artist }
        return try await request(payload)
    }

    static func home() async throws -> HomePayload {
        try await request(["operation": "home"])
    }

    static func genre(params: String) async throws -> [HomeShelfSection] {
        let sections: [HomeSectionPayload] = try await request(["operation": "genre", "params": params])
        return sections.map(\.section)
    }

    static func album(browseID: String) async throws -> AlbumDetailPayload {
        try await request(["operation": "album", "browse_id": browseID])
    }

    static func artist(browseID: String) async throws -> ArtistDetailPayload {
        try await request(["operation": "artist", "browse_id": browseID])
    }

    static func playlist(playlistID: String) async throws -> PlaylistDetailPayload {
        try await request(["operation": "playlist", "playlist_id": playlistID])
    }

    static func radio(videoID: String) async throws -> [MusicTrack] {
        let songs: [Song] = try await request(["operation": "radio", "video_id": videoID])
        var seen: Set<String> = []
        return songs.map(\.track).filter { seen.insert($0.id).inserted }
    }

    static func libraryContent() async throws -> LibraryContentPayload {
        try await request(["operation": "library_content"])
    }

    static func rateTrack(videoID: String, liked: Bool?) async throws {
        let payload: [String: Any] = ["operation": "rate_track", "video_id": videoID, "liked": liked ?? false]
        let _: Status = try await request(payload)
    }

    static func ratePlaylist(playlistID: String, liked: Bool) async throws {
        let _: Status = try await request(["operation": "rate_playlist", "playlist_id": playlistID, "saved": liked])
    }

    static func setArtistSaved(channelID: String, saved: Bool) async throws {
        let _: Status = try await request(["operation": "set_artist_saved", "artist_id": channelID, "saved": saved])
    }

    static func createPlaylist(title: String) async throws -> String {
        let created: CreatedPlaylist = try await request(["operation": "create_playlist", "title": title])
        return created.playlist_id
    }

    static func renamePlaylist(playlistID: String, title: String) async throws {
        let payload: [String: Any] = ["operation": "rename_playlist", "playlist_id": playlistID, "title": title]
        let _: Status = try await request(payload)
    }

    static func deletePlaylist(playlistID: String) async throws {
        let _: Status = try await request(["operation": "delete_playlist", "playlist_id": playlistID])
    }

    static func setPlaylistPrivacy(playlistID: String, privacy: String) async throws {
        let _: Status = try await request(["operation": "set_playlist_privacy", "playlist_id": playlistID, "public": privacy == "PUBLIC"])
    }

    static func addPlaylistTrack(playlistID: String, videoID: String) async throws {
        let _: Status = try await request(["operation": "add_playlist_track", "playlist_id": playlistID, "video_id": videoID])
    }

    static func removePlaylistTrack(playlistID: String, videoID: String, setVideoID: String) async throws {
        let _: Status = try await request([
            "operation": "remove_playlist_track",
            "playlist_id": playlistID,
            "video_id": videoID,
            "set_video_id": setVideoID
        ])
    }

    private static func request<Value: Decodable>(_ request: [String: Any]) async throws -> Value {
        let encoded = try JSONSerialization.data(withJSONObject: request)
        guard let input = String(data: encoded, encoding: .utf8) else { throw ProviderError.unavailable }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let reply = Unmanaged.passRetained(NativeReply(continuation))
            let result = input.withCString { sonora_mobile_request($0, reply.toOpaque(), receiveNativeReply) }
            if result != 0 {
                reply.release()
                continuation.resume(throwing: ProviderError.unavailable)
            }
        }
        try Task.checkCancellation()
        let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: data)
        guard envelope.ok, let value = envelope.data else {
            switch envelope.error {
            case "timeout": throw ProviderError.timeout
            case "sign_in_required": throw ProviderError.signInRequired
            default: throw ProviderError.unavailable
            }
        }
        return value
    }
}

/// Owns a cancellable lyrics request and discards results after a track changes or the sheet closes.
@MainActor @Observable
final class LyricsStore {
    private(set) var sheet: NativeProvider.Lyrics?
    private(set) var isLoading = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func load(_ id: String, title: String? = nil, artist: String? = nil) {
        cancel()
        let generation = UUID()
        self.generation = generation
        isLoading = true
        error = nil
        sheet = nil
        task = Task { [weak self] in
            do {
                let lyrics = try await NativeProvider.lyrics(id, title: title, artist: artist)
                guard let self, self.generation == generation else { return }
                self.sheet = lyrics
                self.isLoading = false
                #if DEBUG
                writeReviewEvidence("lyrics-review.json", ["line_count": lyrics.lines?.count ?? 0, "synced": lyrics.synced ?? false, "has_text": !(lyrics.text ?? "").isEmpty])
                #endif
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoading = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        generation = UUID()
        isLoading = false
    }
}

/// Holds search state across songs, albums, artists, playlists, and suggestions independently of view lifetime.
@MainActor @Observable
final class YouTubeSearch {
    var query = ""
    private(set) var tracks: [MusicTrack] = []
    private(set) var albums: [CatalogAlbum] = []
    private(set) var playlists: [CatalogPlaylist] = []
    private(set) var artists: [CatalogArtist] = []
    private(set) var suggestions: [String] = []
    private(set) var isLoading = false
    private(set) var hasSearched = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func updateSuggestions(_ input: String) {
        suggestionTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { suggestions = []; return }
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if let results = try? await NativeProvider.searchSuggestions(trimmed), !Task.isCancelled {
                self?.suggestions = results
            }
        }
    }

    func submit(_ input: String) {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { clear(); return }
        task?.cancel()
        suggestionTask?.cancel()
        let generation = UUID()
        self.generation = generation
        tracks = []
        albums = []
        playlists = []
        artists = []
        error = nil
        hasSearched = true
        isLoading = true
        task = Task { [weak self] in
            do {
                let catalog = try await NativeProvider.searchCatalog(query)
                guard let self, self.generation == generation else { return }
                var seenTracks: Set<String> = []
                self.tracks = catalog.songs.map(\.track).filter { seenTracks.insert($0.id).inserted }
                self.albums = catalog.albums.map(\.album)
                self.playlists = catalog.playlists.map(\.playlist)
                self.artists = catalog.artists.map(\.artist)
                self.isLoading = false
            } catch is CancellationError {
                // A newer search owns the screen; the old native callback still frees its response.
            } catch {
                guard let self, self.generation == generation else { return }
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoading = false
            }
        }
    }

    func clear() {
        query = ""
        task?.cancel()
        suggestionTask?.cancel()
        generation = UUID()
        tracks = []
        albums = []
        playlists = []
        artists = []
        suggestions = []
        error = nil
        hasSearched = false
        isLoading = false
    }
}

/// Coordinates YouTube Music home shelves, genres, and signed-in library collections (liked songs, albums, playlists, artists).
@MainActor @Observable
final class CatalogStore {
    private(set) var homeSections: [HomeShelfSection] = []
    private(set) var genres: [GenreCategory] = []
    private(set) var likedSongs: [MusicTrack] = []
    private(set) var savedAlbums: [CatalogAlbum] = []
    private(set) var savedPlaylists: [CatalogPlaylist] = []
    private(set) var savedArtists: [CatalogArtist] = []
    private(set) var isLoadingHome = false
    private(set) var isLoadingLibrary = false
    var homeError: String?
    var libraryError: String?
    @ObservationIgnored private var homeTask: Task<Void, Never>?
    @ObservationIgnored private var libraryTask: Task<Void, Never>?

    func loadHome(force: Bool = false) {
        if !force && (!homeSections.isEmpty || isLoadingHome) { return }
        homeTask?.cancel()
        isLoadingHome = true
        homeError = nil
        homeTask = Task { [weak self] in
            do {
                let payload = try await NativeProvider.home()
                guard let self, !Task.isCancelled else { return }
                self.homeSections = payload.sections.map(\.section)
                self.genres = payload.genres.map(\.genre)
                #if DEBUG
                writeReviewEvidence("home-review.json", ["sections": self.homeSections.count, "items": self.homeSections.reduce(0) { $0 + $1.items.count }, "genres": self.genres.count])
                #endif
                self.isLoadingHome = false
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.homeError = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoadingHome = false
            }
        }
    }

    func loadLibrary(isSignedIn: Bool) {
        guard isSignedIn else {
            clearLibrary()
            return
        }
        libraryTask?.cancel()
        isLoadingLibrary = true
        libraryError = nil
        libraryTask = Task { [weak self] in
            do {
                let payload = try await NativeProvider.libraryContent()
                guard let self, !Task.isCancelled else { return }
                var seen: Set<String> = []
                self.likedSongs = payload.liked_songs.map(\.track).filter { seen.insert($0.id).inserted }
                self.savedAlbums = payload.albums.map(\.album)
                self.savedPlaylists = payload.playlists.map(\.playlist)
                self.savedArtists = payload.artists.map(\.artist)
                self.isLoadingLibrary = false
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.libraryError = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoadingLibrary = false
            }
        }
    }

    func clearLibrary() {
        libraryTask?.cancel()
        likedSongs = []
        savedAlbums = []
        savedPlaylists = []
        savedArtists = []
        libraryError = nil
        isLoadingLibrary = false
    }

    func isLiked(_ track: MusicTrack) -> Bool {
        if let liked = track.liked { return liked }
        return likedSongs.contains { $0.id == track.id }
    }

    func toggleLike(_ track: MusicTrack) {
        guard let videoID = track.youtubeID else { return }
        let currentlyLiked = isLiked(track)
        let target: Bool? = currentlyLiked ? nil : true
        if currentlyLiked {
            likedSongs.removeAll { $0.id == track.id }
        } else {
            var updated = track
            updated.liked = true
            likedSongs.insert(updated, at: 0)
        }
        Task {
            try? await NativeProvider.rateTrack(videoID: videoID, liked: target)
        }
    }
}

#if DEBUG
/// Writes only counts for CLI acceptance checks; never stores account secrets, lyrics or stream URLs.
@MainActor
private func writeReviewEvidence(_ filename: String, _ values: [String: Any]) {
    guard ProcessInfo.processInfo.arguments.contains("--sonora-review-url"),
          let data = try? JSONSerialization.data(withJSONObject: values) else { return }
    try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent(filename), options: .atomic)
}
#endif

#if DEBUG
/// Tests several real public search results so one gated video cannot stand in for all Guest playback.
@MainActor
final class GuestAcceptanceProbe {
    private var task: Task<Void, Never>?

    func start(playback: PlaybackController, selected: @escaping () -> Void) {
        task?.cancel()
        task = Task {
            var results: [[String: String]] = []
            do {
                let tracks = try await NativeProvider.search("Beethoven")
                for track in tracks.filter({ $0.available != false }).prefix(4) {
                    guard !Task.isCancelled, let id = track.youtubeID else { return }
                    do {
                        _ = try await NativeProvider.resolve(id)
                        results.append(["id": id, "result": "resolved"])
                        writeReviewEvidence("guest-probe.json", ["status": "selected", "selected_id": id, "candidates": results])
                        playback.play(track, in: [track])
                        selected()
                        return
                    } catch {
                        let code: String
                        switch error as? ProviderError {
                        case .signInRequired: code = "sign_in_required"
                        case .timeout: code = "timeout"
                        default: code = "provider_unavailable"
                        }
                        results.append(["id": id, "result": code])
                        writeReviewEvidence("guest-probe.json", ["status": "running", "candidates": results])
                    }
                }
            } catch {
                results.append(["result": "search_failed"])
            }
            writeReviewEvidence("guest-probe.json", ["status": "failed", "candidates": results])
        }
    }
}
#endif
