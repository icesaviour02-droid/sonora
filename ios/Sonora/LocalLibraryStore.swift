import Foundation
import Observation

struct LocalPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let modified_at: Int64
    let track_ids: [String]

    func tracks(in library: [MusicTrack]) -> [MusicTrack] {
        let indexed = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return track_ids.compactMap { indexed[$0] }
    }
}

struct LocalLibrarySnapshot: Decodable {
    let playlists: [LocalPlaylist]
    let track_ids: [String]
    let album_ids: [String]
    let artist_ids: [String]
    let created_id: String?
}

enum LocalFavoriteCategory: String { case tracks, albums, artists }

/// Serializes user mutations and publishes snapshots from the exact desktop SQLite store.
@MainActor @Observable
final class LocalLibraryStore {
    private(set) var playlists: [LocalPlaylist] = []
    private(set) var favoriteTrackOrder: [String] = []
    private(set) var favoriteAlbumOrder: [String] = []
    private(set) var favoriteArtistOrder: [String] = []
    private(set) var favoriteTracks: Set<String> = []
    private(set) var favoriteAlbums: Set<String> = []
    private(set) var favoriteArtists: Set<String> = []
    private(set) var isLoaded = false
    private(set) var isBusy = false
    var error: String?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var pending = 0
    private let databaseURL: URL

    init(databaseURL: URL = URL.applicationSupportDirectory.appendingPathComponent("State/local-library.sqlite")) {
        self.databaseURL = databaseURL
    }

    func load() async {
        guard !isLoaded else { return }
        await perform(["kind": "snapshot"]).value
    }

    func refresh() { perform(["kind": "snapshot"]) }

    func playlist(_ id: String) -> LocalPlaylist? { playlists.first { $0.id == id } }

    func create(name: String, tracks: [String] = [], completed: @escaping (String) -> Void = { _ in }) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !name.isEmpty else { return }
        perform(["kind": "create_playlist", "name": name, "track_ids": tracks], completed: { response in
            if let id = response.created_id { completed(id) }
        })
    }

    func rename(_ id: String, name: String, completed: @escaping () -> Void = {}) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !name.isEmpty else { return }
        perform(["kind": "rename_playlist", "playlist_id": id, "name": name], completed: { _ in completed() })
    }

    func delete(_ id: String) { perform(["kind": "delete_playlist", "playlist_id": id]) }

    func add(_ trackIDs: [String], to id: String, completed: @escaping () -> Void = {}) {
        perform(["kind": "add_tracks", "playlist_id": id, "track_ids": trackIDs], completed: { _ in completed() })
    }

    func remove(_ trackIDs: [String], from id: String) {
        perform(["kind": "remove_tracks", "playlist_id": id, "track_ids": trackIDs])
    }

    func reorder(_ trackIDs: [String], in id: String) {
        guard !isBusy, let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let original = playlists[index]
        guard Set(trackIDs).count == trackIDs.count, Set(trackIDs) == Set(original.track_ids) else {
            error = String(localized: "ios-local-library-error")
            return
        }
        // Native drag editing needs the new order synchronously, before its save finishes.
        playlists[index] = LocalPlaylist(id: original.id, title: original.title,
            modified_at: original.modified_at, track_ids: trackIDs)
        perform(["kind": "reorder_playlist", "playlist_id": id, "track_ids": trackIDs], rollback: { [weak self] in
            if let self, let index = self.playlists.firstIndex(where: { $0.id == id }) { self.playlists[index] = original }
        })
    }

    func forget(_ trackIDs: [String]) {
        guard !trackIDs.isEmpty else { return }
        perform(["kind": "forget_tracks", "track_ids": trackIDs])
    }

    func isFavorite(_ id: String, category: LocalFavoriteCategory) -> Bool {
        switch category {
        case .tracks: favoriteTracks.contains(id)
        case .albums: favoriteAlbums.contains(id)
        case .artists: favoriteArtists.contains(id)
        }
    }

    func toggleFavorite(_ id: String, category: LocalFavoriteCategory) {
        // Swift considers canonically equivalent names equal; SQLite compares their actual bytes.
        let identity = category == .tracks ? id : id.precomposedStringWithCanonicalMapping
        perform(["kind": "toggle_favorite", "category": category.rawValue, "id": identity])
    }

    /// Mutations never cancel earlier writes. Errors preserve the database and the last good view.
    @discardableResult
    private func perform(_ action: [String: Any], rollback: @escaping () -> Void = {},
                         completed: @escaping (LocalLibrarySnapshot) -> Void = { _ in }) -> Task<Void, Never> {
        let previous = operation
        pending += 1
        isBusy = true
        error = nil
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.pending -= 1; self.isBusy = self.pending > 0 }
            do {
                let response = try await NativeProvider.localLibrary(at: self.databaseURL, action: action)
                self.apply(response)
                completed(response)
            } catch {
                rollback()
                if let fresh = try? await NativeProvider.localLibrary(at: self.databaseURL, action: ["kind": "snapshot"]) { self.apply(fresh) }
                self.error = String(localized: "ios-local-library-error")
            }
        }
        operation = task
        return task
    }

    private func apply(_ response: LocalLibrarySnapshot) {
        playlists = response.playlists
        favoriteTrackOrder = response.track_ids
        favoriteAlbumOrder = response.album_ids
        favoriteArtistOrder = response.artist_ids
        favoriteTracks = Set(response.track_ids)
        favoriteAlbums = Set(response.album_ids)
        favoriteArtists = Set(response.artist_ids)
        isLoaded = true
    }
}
