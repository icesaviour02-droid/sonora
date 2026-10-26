import SwiftUI

/// A native creation form can start empty or carry the songs selected by an Add to Playlist action.
struct CreateLocalPlaylistView: View {
    @Environment(LocalLibraryStore.self) private var local
    @Environment(\.dismiss) private var dismiss
    let trackIDs: [String]
    var created: (String) -> Void = { _ in }
    @State private var name = ""
    @State private var visible = false

    var body: some View {
        Form {
            TextField("ios-playlist-title", text: $name)
            Text("ios-local-playlists-description").foregroundStyle(.secondary)
            if let error = local.error { Text(error).foregroundStyle(.secondary) }
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .navigationTitle("ios-create-playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-create") {
                    local.create(name: name, tracks: trackIDs) { id in if visible { created(id); dismiss() } }
                }
                .disabled(local.isBusy || !local.isLoaded || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

/// The same song label appears in playback lists and selection lists; choosing songs never starts audio.
struct LocalSongsPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let excluded: Set<String>
    let add: ([String]) -> Void
    @State private var selected: Set<String> = []
    @State private var query = ""

    private var tracks: [MusicTrack] {
        library.tracks.filter { !excluded.contains($0.id) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || $0.albumTitle?.localizedCaseInsensitiveContains(query) == true) }
    }

    var body: some View {
        List(selection: $selected) {
            ForEach(tracks) { track in TrackRow(track: track) {}.selecting().tag(track.id) }
        }
        .environment(\.editMode, .constant(.active))
        .searchable(text: $query)
        .overlay { if tracks.isEmpty { ContentUnavailableView("ios-songs", systemImage: "music.note") } }
        .navigationTitle("ios-add-songs")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-add") {
                    add(library.tracks.filter { selected.contains($0.id) }.map(\.id))
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
    }
}

/// Imported songs can be put into a saved playlist without a streaming account or network access.
struct AddToLocalPlaylistView: View {
    @Environment(LocalLibraryStore.self) private var local
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let trackIDs: [String]
    @State private var create = false

    var body: some View {
        List {
            Button("ios-create-playlist", systemImage: "plus") { create = true }
                .disabled(local.isBusy || !local.isLoaded)
            ForEach(local.playlists) { playlist in
                Button {
                    local.add(trackIDs, to: playlist.id) { dismiss() }
                } label: { LocalPlaylistLabel(playlist: playlist, tracks: playlist.tracks(in: library.tracks)) }
                .disabled(local.isBusy)
            }
            if let error = local.error { Text(error).foregroundStyle(.secondary) }
        }
        .navigationTitle("ios-add-to-playlist")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } } }
        .sheet(isPresented: $create) {
            NavigationStack { CreateLocalPlaylistView(trackIDs: trackIDs) { _ in dismiss() } }
        }
    }
}

struct LocalPlaylistLabel: View {
    let playlist: LocalPlaylist
    let tracks: [MusicTrack]

    var body: some View {
        HStack(spacing: Layout.spacing) {
            ArtworkView(track: tracks.first { $0.displayArtworkURL != nil } ?? tracks.first, side: Layout.rowArtwork).placeholderSymbol("music.note.list")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(playlist.title).appFont(.body, weight: .medium).foregroundStyle(.primary).lineLimit(2)
                Text("ios-on-my-iphone").appFont(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Native row editing changes the stored order, while stale snapshots are rejected by the database.
struct LocalPlaylistView: View {
    @Environment(LocalLibraryStore.self) private var local
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let playlistID: String
    @State private var picking = false
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var name = ""
    private var playlist: LocalPlaylist? { local.playlist(playlistID) }
    @State private var showNavigationTitle = false
    @State private var editMode = EditMode.inactive
    private var tracks: [MusicTrack] { playlist?.tracks(in: library.tracks) ?? [] }
    private var indexed: [String: MusicTrack] { Dictionary(library.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    var body: some View {
        let byID = indexed
        Group {
            if let playlist {
                List {
                    header(playlist)
                    if tracks.isEmpty {
                        ContentUnavailableView("ios-songs", systemImage: "music.note", description: Text("ios-local-empty-playlist"))
                            .listRowSeparator(.hidden)
                    }
                    ForEach(playlist.track_ids, id: \.self) { id in
                        Group {
                            if let track = byID[id] { TrackRow(track: track) { playback.play(track, in: tracks) } }
                            else { Label("ios-track-unavailable", systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
                        }
                        .deleteDisabled(local.isBusy).moveDisabled(local.isBusy)
                    }
                    .onDelete { offsets in local.remove(offsets.map { playlist.track_ids[$0] }, from: playlistID) }
                    .onMove { offsets, destination in
                        var order = playlist.track_ids
                        order.move(fromOffsets: offsets, toOffset: destination)
                        local.reorder(order, in: playlistID)
                    }
                    if let error = local.error { Text(error).foregroundStyle(.secondary) }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y > Layout.collectionArtwork
                } action: { _, collapsed in showNavigationTitle = collapsed }
            } else { ContentUnavailableView("ios-playlists", systemImage: "music.note.list", description: Text("ios-local-playlist-missing")) }
        }
        .navigationTitle(showNavigationTitle ? (playlist?.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .confirmationAction) { Button("ios-done") { editMode = .inactive } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios-edit-playlist", systemImage: "pencil") { editMode = .active }
                        .disabled(playlist?.track_ids.isEmpty ?? true)
                    Button("ios-add-songs", systemImage: "plus") { picking = true }
                    Button("ios-rename-playlist", systemImage: "pencil") { name = playlist?.title ?? ""; renaming = true }
                        .accessibilityIdentifier("playlist-rename")
                    Button("ios-delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis") }
                .disabled(local.isBusy || playlist == nil).accessibilityIdentifier("playlist-more")
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack { LocalSongsPicker(excluded: Set(playlist?.track_ids ?? [])) { local.add($0, to: playlistID) } }
        }
        .alert("ios-rename-playlist", isPresented: $renaming) {
            TextField("ios-playlist-title", text: $name)
            Button("ios-save") { local.rename(playlistID, name: name) }.accessibilityIdentifier("playlist-save-name")
            Button("ios-cancel", role: .cancel) {}
        }
        .confirmationDialog("ios-delete-playlist", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("ios-delete", role: .destructive) { local.delete(playlistID) }
            Button("ios-cancel", role: .cancel) {}
        }
        .onChange(of: local.playlists) { _, _ in if playlist == nil { dismiss() } }
    }

    private func header(_ playlist: LocalPlaylist) -> some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            MusicCollectionHeader(title: playlist.title, subtitle: String(localized: "ios-on-my-iphone"),
                artworkURL: tracks.first { $0.displayArtworkURL != nil }?.displayArtworkURL, tracks: tracks)
            Button("ios-add-songs", systemImage: "plus") { picking = true }
                .appFont(.body, weight: .semibold)
                .frame(minHeight: Layout.control)
                .disabled(local.isBusy)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// These menu items are reused by song rows and the expanded player.
struct LocalTrackActions: View {
    @Environment(LocalLibraryStore.self) private var local
    let track: MusicTrack
    let choosePlaylist: () -> Void

    var body: some View {
        Button(local.isFavorite(track.id, category: .tracks) ? "ios-remove-favorite" : "ios-favorite",
               systemImage: local.isFavorite(track.id, category: .tracks) ? "star.slash" : "star") {
            local.toggleFavorite(track.id, category: .tracks)
        }.disabled(local.isBusy || !local.isLoaded)
        Button("ios-add-to-playlist", systemImage: "music.note.list", action: choosePlaylist)
            .disabled(!local.isLoaded)
    }
}

/// Server-side creation stays owned by catalog state even if the sheet is dismissed.
struct YouTubePlaylistCreationView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        Form {
            TextField("ios-playlist-title", text: $title)
            Text("ios-private-playlist-description").foregroundStyle(.secondary)
            if let error = catalog.libraryError { Text(error).foregroundStyle(.secondary) }
        }
        .navigationTitle("ios-create-playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-create") {
                    catalog.createPlaylist(title: title.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                }.disabled(catalog.isCreatingPlaylist || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

/// Local favorites survive sign-out and cache removal because they live in the durable database.
struct LocalFavoritesView: View {
    @Environment(LocalLibraryStore.self) private var local
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    private var songs: [MusicTrack] {
        let indexed = Dictionary(library.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return local.favoriteTrackOrder.compactMap { indexed[$0] }
    }
    private var albums: [LocalAlbum] {
        let indexed = Dictionary(LocalAlbum.collect(library.tracks).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return local.favoriteAlbumOrder.compactMap { indexed[$0] }
    }
    private var artists: [String] {
        let indexed = Dictionary(library.tracks.map { ($0.artist.lowercased(), $0.artist) }, uniquingKeysWith: { first, _ in first })
        return local.favoriteArtistOrder.compactMap { indexed[$0] }
    }

    var body: some View {
        List {
            Section("ios-songs") {
                ForEach(songs) { track in TrackRow(track: track) { playback.play(track, in: songs) } }
            }
            Section("ios-albums") {
                ForEach(albums) { album in
                    NavigationLink { LocalAlbumView(albumID: album.id) } label: {
                        HStack(spacing: Layout.spacing) {
                            ArtworkView(track: album.tracks.first, side: Layout.rowArtwork)
                            VStack(alignment: .leading) { Text(album.title); Text(album.artist).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("ios-artists") {
                ForEach(artists, id: \.self) { artist in
                    NavigationLink(artist) { LocalArtistView(name: artist) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty && albums.isEmpty && artists.isEmpty {
                ContentUnavailableView("ios-local-favorites", systemImage: "star")
            }
        }
        .navigationTitle("ios-local-favorites")
    }
}
