import Foundation
import Observation
import SwiftUI

/// Contains only an isolated review database and actual imported, generated audio recordings.
struct LocalPlaylistReviewPresentation: Identifiable {
    let id: String
    let store: LocalLibraryStore
}

#if DEBUG
@MainActor @Observable
final class LocalLibraryReview {
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Exercises the Swift state queue and Codable boundary before presenting the real native screen.
    func start(library: LibraryStore, ready: @escaping (LocalPlaylistReviewPresentation) -> Void) {
        task?.cancel()
        task = Task {
            var checks: [String: Bool] = [:]
            let directory = URL.cachesDirectory.appendingPathComponent("LocalLibraryReview/" + UUID().uuidString)
            let database = directory.appendingPathComponent("state.sqlite")
            let store = LocalLibraryStore(databaseURL: database)
            await store.load()
            checks["initial_snapshot"] = store.isLoaded && store.playlists.isEmpty
            guard let first = await library.importReviewRecording(), let second = await library.importReviewRecording() else {
                checks["generated_media_import"] = false
                Self.record(checks)
                return
            }
            checks["generated_media_import"] = true
            var identity: String?
            store.create(name: "Sonora Local Review", tracks: [first.id, second.id, first.id]) { identity = $0 }
            await Self.wait(store)
            guard let id = identity else { checks["create_playlist"] = false; Self.record(checks); return }
            checks["create_playlist"] = store.playlist(id)?.track_ids == [first.id, second.id]
            store.rename(id, name: "Sonora Saved Playlist")
            store.add([first.id], to: id)
            await Self.wait(store)
            checks["queued_mutations"] = store.playlist(id)?.title == "Sonora Saved Playlist" && store.playlist(id)?.track_ids.count == 2
            store.reorder([second.id, first.id], in: id)
            await Self.wait(store)
            checks["reorder"] = store.playlist(id)?.track_ids == [second.id, first.id]
            store.reorder([first.id], in: id)
            await Self.wait(store)
            checks["stale_reorder_keeps_state"] = store.error != nil && store.playlist(id)?.track_ids == [second.id, first.id]
            store.toggleFavorite(first.id, category: .tracks)
            store.toggleFavorite("review-album", category: .albums)
            store.toggleFavorite("review-artist", category: .artists)
            await Self.wait(store)
            checks["favorite_categories"] = store.favoriteTracks.contains(first.id) && store.favoriteAlbums.contains("review-album") && store.favoriteArtists.contains("review-artist")
            store.toggleFavorite(first.id, category: .tracks)
            store.toggleFavorite(first.id, category: .tracks)
            await Self.wait(store)
            checks["queued_toggles"] = store.favoriteTracks.contains(first.id)
            store.toggleFavorite("Cafe\u{301}", category: .albums)
            store.toggleFavorite("Caf\u{e9}", category: .albums)
            await Self.wait(store)
            checks["canonical_unicode_favorite"] = !store.favoriteAlbums.contains("Caf\u{e9}")
            let restored = LocalLibraryStore(databaseURL: database)
            await restored.load()
            checks["disk_restore"] = restored.playlist(id)?.track_ids == [second.id, first.id] && restored.favoriteTracks.contains(first.id)
            var temporary: String?
            store.create(name: "Temporary Review", tracks: [first.id]) { temporary = $0 }
            await Self.wait(store)
            if let temporary { store.delete(temporary); await Self.wait(store) }
            checks["delete_one_playlist"] = store.playlists.count == 1 && store.playlist(id) != nil
            store.forget([first.id])
            await Self.wait(store)
            checks["deleted_import_cleanup"] = store.playlist(id)?.track_ids == [second.id] && !store.favoriteTracks.contains(first.id)
            store.add([first.id], to: id)
            await Self.wait(store)
            checks["ordered_playable_tracks"] = store.playlist(id)?.tracks(in: library.tracks).map(\.id) == [second.id, first.id]
            let manifest = Manifest(database: database.path, playlist: id, tracks: [second.id, first.id])
            if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: Self.manifestURL, options: .atomic) }
            Self.record(checks)
            ready(LocalPlaylistReviewPresentation(id: id, store: store))
        }
    }

    private struct Manifest: Codable { let database: String; let playlist: String; let tracks: [String] }
    private static var manifestURL: URL { URL.cachesDirectory.appendingPathComponent("local-library-presentation.json") }

    /// Reopens the review database and imported audio after the runner terminates the first app.
    func restore(library: LibraryStore, ready: @escaping (LocalPlaylistReviewPresentation) -> Void) {
        task?.cancel()
        task = Task {
            var checks: [String: Bool] = [:]
            if let data = try? Data(contentsOf: Self.manifestURL), let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
                let database = URL(fileURLWithPath: manifest.database).standardizedFileURL
                let allowed = URL.cachesDirectory.appendingPathComponent("LocalLibraryReview").standardizedFileURL.path + "/"
                if database.path.hasPrefix(allowed) {
                    let store = LocalLibraryStore(databaseURL: database)
                    await store.load()
                    checks["database_reopened"] = store.isLoaded
                    checks["playlist_order_restored"] = store.playlist(manifest.playlist)?.track_ids == manifest.tracks
                    checks["imported_media_resolved"] = store.playlist(manifest.playlist)?.tracks(in: library.tracks).map(\.id) == manifest.tracks
                    checks["favorites_restored"] = store.favoriteAlbums.contains("review-album") && store.favoriteArtists.contains("review-artist")
                    ready(LocalPlaylistReviewPresentation(id: manifest.playlist, store: store))
                }
            }
            let result: [String: Any] = ["passed": checks.count == 4 && checks.values.allSatisfy { $0 }, "checks": checks]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) {
                try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("local-library-relaunch-review.json"), options: .atomic)
            }
        }
    }

    private static func wait(_ store: LocalLibraryStore) async {
        for _ in 0..<500 {
            if !store.isBusy || Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func record(_ checks: [String: Bool]) {
        let result: [String: Any] = ["passed": checks.count == 13 && checks.values.allSatisfy { $0 }, "checks": checks]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) {
            try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("local-library-review.json"), options: .atomic)
        }
    }
}
#endif

/// Release builds have no review presentation; the modifier keeps the main root layout identical.
struct LocalLibraryReviewSheet: ViewModifier {
    @Binding var presentation: LocalPlaylistReviewPresentation?
    func body(content: Content) -> some View {
        #if DEBUG
        content.sheet(item: $presentation) { value in
            NavigationStack { LocalPlaylistView(playlistID: value.id) }.environment(value.store)
        }
        #else
        content
        #endif
    }
}
