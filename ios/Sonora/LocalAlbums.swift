import Foundation
import SwiftUI

/// Album artist keeps compilations together; disc and track tags preserve the record's order.
struct LocalAlbum: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [MusicTrack]

    static func collect(_ tracks: [MusicTrack]) -> [LocalAlbum] {
        let grouped = Dictionary(grouping: tracks.filter { !($0.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { track in
            (track.albumTitle ?? "").lowercased() + "\0" + (track.albumArtist ?? track.artist).lowercased()
        }
        return grouped.compactMap { (key, tracks) -> LocalAlbum? in
            guard let first = tracks.first else { return nil }
            let ordered = tracks.sorted {
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                if ($0.trackNumber ?? .max) != ($1.trackNumber ?? .max) { return ($0.trackNumber ?? .max) < ($1.trackNumber ?? .max) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return LocalAlbum(id: key, title: first.albumTitle ?? "", artist: first.albumArtist ?? first.artist, tracks: ordered)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// Local albums use the same artwork, controls and song rows as provider records.
struct LocalAlbumView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var local
    @State private var choosePlaylist = false
    @Environment(PlaybackController.self) private var playback
    let albumID: String
    private var album: LocalAlbum? { LocalAlbum.collect(library.tracks).first { $0.id == albumID } }

    var body: some View {
        Group {
            if let album {
                List {
                    MusicCollectionHeader(title: album.title, subtitle: album.artist,
                        artworkURL: album.tracks.first { $0.displayArtworkURL != nil }?.displayArtworkURL,
                        tracks: album.tracks, symbol: "square.stack")
                    ForEach(album.tracks) { track in
                        TrackRow(track: track) { playback.play(track, in: album.tracks) }
                    }
                }
                .listStyle(.plain)
            } else { ContentUnavailableView("ios-albums", systemImage: "square.stack") }
        }
        .navigationTitle(album?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let album {
                        Button(local.isFavorite(album.id, category: .albums) ? "ios-remove-favorite" : "ios-favorite",
                               systemImage: local.isFavorite(album.id, category: .albums) ? "star.slash" : "star") {
                            local.toggleFavorite(album.id, category: .albums)
                        }.disabled(local.isBusy || !local.isLoaded)
                        Button("ios-add-to-playlist", systemImage: "music.note.list") { choosePlaylist = true }
                            .disabled(!local.isLoaded)
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $choosePlaylist) {
            NavigationStack { AddToLocalPlaylistView(trackIDs: album?.tracks.map(\.id) ?? []) }
        }
    }
}

/// Reuses the imported song and album surfaces for a local artist, including favorite controls.
struct LocalArtistView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var local
    @Environment(PlaybackController.self) private var playback
    let name: String
    private var tracks: [MusicTrack] { library.tracks.filter { $0.artist.lowercased() == name.lowercased() } }

    var body: some View {
        List {
            Section {
                HStack(spacing: Layout.spacing) {
                    Button("ios-play", systemImage: "play.fill") { if let first = tracks.first { playback.play(first, in: tracks) } }
                        .buttonStyle(.glassProminent)
                    Button("ios-shuffle", systemImage: "shuffle") { playback.playShuffled(tracks) }.buttonStyle(.glass)
                }.disabled(tracks.isEmpty)
            }
            Section("ios-albums") {
                ForEach(LocalAlbum.collect(tracks)) { album in
                    NavigationLink { LocalAlbumView(albumID: album.id) } label: {
                        HStack(spacing: Layout.spacing) { ArtworkView(track: album.tracks.first, side: Layout.rowArtwork); Text(album.title) }
                    }
                }
            }
            Section("ios-songs") {
                ForEach(tracks) { track in TrackRow(track: track) { playback.play(track, in: tracks) } }
            }
        }
        .listStyle(.plain)
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(local.isFavorite(name.lowercased(), category: .artists) ? "ios-remove-favorite" : "ios-favorite",
                       systemImage: local.isFavorite(name.lowercased(), category: .artists) ? "star.fill" : "star") {
                    local.toggleFavorite(name.lowercased(), category: .artists)
                }.disabled(local.isBusy || !local.isLoaded)
            }
        }
    }
}
