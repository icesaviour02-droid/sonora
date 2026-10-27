import SwiftUI

/// Downloaded music mirrors Library categories; active transfers have separate, actionable rows.
struct DownloadsView: View {
    @Environment(DownloadsStore.self) private var downloads
    @State private var selectedRecent: MusicTrack?
    private var tracks: [MusicTrack] { downloads.completedTracks }
    private var pending: [DownloadEntry] { downloads.entries.filter { $0.state != .downloaded } }
    private var recentCollections: [MusicTrack] {
        var seen = Set<String>()
        return Array(tracks.reversed().filter { track in
            let title = (track.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.isEmpty ? track.id : (track.albumID ?? title.lowercased() + "\0" + (track.albumArtist ?? track.artist).lowercased())
            return seen.insert(key).inserted
        }.prefix(8))
    }

    var body: some View {
        List {
            if !tracks.isEmpty {
                Section {
                    NavigationLink { DownloadedPlaylistsView() } label: { Label("ios-playlists", systemImage: "music.note.list") }.accessibilityIdentifier("download-playlists")
                    NavigationLink { DownloadedArtistsView() } label: { Label("ios-artists", systemImage: "music.mic") }.accessibilityIdentifier("download-artists")
                    NavigationLink { DownloadedAlbumsView() } label: { Label("ios-albums", systemImage: "square.stack") }.accessibilityIdentifier("download-albums")
                    NavigationLink { DownloadedSongsView() } label: { Label("ios-songs", systemImage: "music.note") }.accessibilityIdentifier("download-songs")
                }.labelStyle(LibraryCategoryLabelStyle())
            }
            if !pending.isEmpty {
                Section("ios-downloading") {
                    ForEach(pending) { entry in DownloadTransferRow(entry: entry) }
                }
            }
            if let error = downloads.error {
                Section { Text(error).appFont(.subheadline).foregroundStyle(.secondary) }
            }
            if !tracks.isEmpty {
                Section("ios-recently-downloaded") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.cardArtwork), spacing: Layout.spacing)],
                              alignment: .leading, spacing: Layout.spacing) {
                        ForEach(recentCollections) { track in
                            Button { selectedRecent = track } label: {
                                SquareCard(title: track.albumTitle ?? track.title, subtitle: track.artist,
                                    artworkURL: track.displayArtworkURL, fillsColumn: true)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Layout.compact)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .appNavigationTitle("ios-downloads")
        .navigationDestination(item: $selectedRecent) { track in
            DownloadedCollectionView(title: track.albumTitle ?? track.title, subtitle: track.artist,
                artwork: track.displayArtworkURL, trackIDs: albumTracks(for: track).map(\.id))
        }
        .overlay {
            if downloads.isRestoring { ProgressView("ios-restoring-downloads") }
            else if downloads.entries.isEmpty {
                ContentUnavailableView("ios-downloads-empty", systemImage: "arrow.down.circle",
                    description: Text("ios-downloads-description"))
            }
        }
    }

    private func albumTracks(for track: MusicTrack) -> [MusicTrack] {
        guard let album = LocalAlbum.collect(tracks).first(where: { $0.tracks.contains { $0.id == track.id } }) else { return [track] }
        return album.tracks
    }
}

/// A transfer's controls stay enabled while its song is not yet playable.
private struct DownloadTransferRow: View {
    @Environment(DownloadsStore.self) private var downloads
    let entry: DownloadEntry
    var body: some View {
        HStack(spacing: Layout.spacing) {
            ArtworkView(track: entry.track, side: Layout.rowArtwork)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(entry.track.title).appFont(.body).lineLimit(1)
                Text(entry.track.artist).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if entry.state == .downloading {
                    ProgressView(value: entry.progress).accessibilityLabel(Text("ios-download-progress"))
                }
                Text(status).appFont(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.state == .failed {
                Button { downloads.retry(entry.id) } label: { Image(systemName: "arrow.clockwise").frame(width: Layout.control, height: Layout.control) }
                    .buttonStyle(.borderless).accessibilityLabel(Text("ios-retry"))
            }
            Button { downloads.remove(entry.id) } label: {
                Image(systemName: "xmark.circle").frame(width: Layout.control, height: Layout.control)
            }.buttonStyle(.borderless).accessibilityLabel(Text("ios-cancel-download"))
        }
        .swipeActions { Button("ios-remove-download", role: .destructive) { downloads.remove(entry.id) } }
    }

    private var status: LocalizedStringKey {
        switch entry.state {
        case .queued: "ios-download-queued"
        case .resolving: "ios-download-preparing"
        case .downloading: "ios-downloading"
        case .downloaded: "ios-downloaded"
        case .failed:
            if entry.failureCode == "size_mismatch" || entry.failureCode == "unplayable" { "ios-download-invalid" }
            else if entry.failureCode?.hasPrefix("file_") == true { "ios-download-storage-failed" }
            else { "ios-download-failed" }
        }
    }
}

/// Search and sorting apply only to completed files. Transfer rows never start a stream.
struct DownloadedSongsView: View {
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback
    @State private var query = ""
    @State private var sort = DownloadSort.title
    private var tracks: [MusicTrack] { sort.tracks(downloads.completedTracks).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            CollectionPlayShuffleHeader(playAction: { if let first = tracks.first { playback.play(first, in: tracks) } },
                shuffleAction: { playback.playShuffled(tracks) }).disabled(tracks.isEmpty).listRowSeparator(.hidden)
            if sort == .title || sort == .artist {
                ForEach(LibraryAlphabet.groups(tracks, title: { sort == .artist ? $0.artist : $0.title })) { group in
                    Section {
                        ForEach(group.items) { track in songRow(track) }
                    } header: { Text(group.id).appFont(.headline) }
                    .sectionIndexLabel(Text(group.id))
                }
            } else {
                ForEach(tracks) { track in songRow(track) }
            }
        }
        .listSectionIndexVisibility(sort == .recent ? .hidden : .visible)
        .listStyle(.plain).searchable(text: $query).appNavigationTitle("ios-songs")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("ios-sort-by", selection: $sort) { ForEach(DownloadSort.allCases) { Text($0.label).tag($0) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel(Text("ios-sort-by"))
        } }
    }
    private func songRow(_ track: MusicTrack) -> some View {
        TrackRow(track: track) { playback.play(track, in: tracks, source: String(localized: "ios-downloads")) }
            .swipeActions { Button("ios-remove-download", role: .destructive) { downloads.remove(track.id) } }
    }

}

private enum DownloadSort: String, CaseIterable, Identifiable {
    case recent, title, artist
    var id: String { rawValue }
    var label: LocalizedStringKey { switch self { case .recent: "ios-recently-downloaded"; case .title: "ios-title"; case .artist: "ios-artists" } }
    func tracks(_ tracks: [MusicTrack]) -> [MusicTrack] {
        switch self {
        case .recent: Array(tracks.reversed())
        case .title: tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: tracks.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        }
    }
}

struct DownloadedAlbumsView: View {
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback
    @AppStorage("sonora.downloaded-albums.grid") private var grid = true
    private var albums: [LocalAlbum] { LocalAlbum.collect(downloads.completedTracks) }

    var body: some View {
        List {
            CollectionPlayShuffleHeader(playAction: {
                if let first = downloads.completedTracks.first { playback.play(first, in: downloads.completedTracks) }
            }, shuffleAction: { playback.playShuffled(downloads.completedTracks) })
                .disabled(downloads.completedTracks.isEmpty).listRowSeparator(.hidden)
            ForEach(LibraryAlphabet.groups(albums, title: { $0.artist })) { group in
                Section {
                    if grid { CollectionGridRows(group.items) { album in albumLink(album) } }
                    else { ForEach(group.items) { album in albumLink(album) } }
                } header: { Text(group.id).appFont(.headline) }
                .sectionIndexLabel(Text(group.id))
            }
        }
        .listStyle(.plain).listSectionIndexVisibility(.visible).appNavigationTitle("ios-albums")
        .toolbar { ToolbarItem(placement: .primaryAction) { CollectionGridMenu(grid: $grid) } }
    }

    private func albumLink(_ album: LocalAlbum) -> some View {
        NavigationLink {
            DownloadedCollectionView(title: album.title, subtitle: album.artist,
                artwork: album.tracks.first?.displayArtworkURL, trackIDs: album.tracks.map(\.id))
        } label: {
            if grid {
                SquareCard(title: album.title, subtitle: album.artist, artworkURL: album.tracks.first?.displayArtworkURL,
                    fillsColumn: true)
            } else {
                DownloadedCollectionLabel(title: album.title, subtitle: album.artist, artwork: album.tracks.first?.displayArtworkURL)
            }
        }.buttonStyle(.plain)
    }
}

struct DownloadedArtistsView: View {
    @Environment(DownloadsStore.self) private var downloads
    private var names: [String] { Array(Set(downloads.completedTracks.map(\.artist))) }
    var body: some View {
        List {
            ForEach(LibraryAlphabet.groups(names, title: { $0 })) { group in
                Section {
                    ForEach(group.items, id: \.self) { name in
                        let tracks = downloads.completedTracks.filter { $0.artist == name }
                        NavigationLink {
                            DownloadedCollectionView(title: name, subtitle: String(localized: "ios-downloaded"),
                                artwork: tracks.first?.displayArtworkURL, trackIDs: tracks.map(\.id))
                        } label: {
                            HStack(spacing: Layout.spacing) {
                                ArtworkView(url: tracks.first?.displayArtworkURL, side: Layout.rowArtwork)
                                    .placeholderSymbol("music.mic").clipShape(Circle())
                                Text(name).appFont(.body)
                            }
                        }
                    }
                } header: { Text(group.id).appFont(.headline) }
                .sectionIndexLabel(Text(group.id))
            }
        }.listStyle(.plain).listSectionIndexVisibility(.visible).appNavigationTitle("ios-artists")
    }
}

struct DownloadedPlaylistsView: View {
    @Environment(DownloadsStore.self) private var downloads
    @AppStorage("sonora.downloaded-playlists.grid") private var grid = true
    private var playlists: [DownloadedPlaylist] {
        downloads.playlists.filter { !downloads.tracks(in: $0).isEmpty }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        List {
            if grid { CollectionGridRows(playlists) { playlist in playlistLink(playlist) } }
            else { ForEach(playlists) { playlist in playlistLink(playlist) } }
        }.listStyle(.plain).appNavigationTitle("ios-playlists")
        .toolbar { ToolbarItem(placement: .primaryAction) { CollectionGridMenu(grid: $grid) } }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView("ios-playlists", systemImage: "music.note.list",
                    description: Text("ios-downloaded-playlists-description"))
            }
        }
    }

    private func playlistLink(_ playlist: DownloadedPlaylist) -> some View {
        NavigationLink {
            DownloadedCollectionView(title: playlist.title, subtitle: playlist.author,
                artwork: playlist.artworkURL, trackIDs: playlist.trackIDs)
        } label: {
            if grid {
                SquareCard(title: playlist.title, subtitle: playlist.author, artworkURL: playlist.artworkURL, fillsColumn: true)
            } else { DownloadedCollectionLabel(title: playlist.title, subtitle: playlist.author, artwork: playlist.artworkURL) }
        }.buttonStyle(.plain)
    }
}

/// Resolves saved IDs against available files on every render, including removals while browsing.
struct DownloadedCollectionView: View {
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback
    let title: String
    let subtitle: String
    let artwork: URL?
    let trackIDs: [String]
    private var tracks: [MusicTrack] {
        let byID = Dictionary(downloads.completedTracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return trackIDs.compactMap { byID[$0] }
    }
    var body: some View {
        List {
            MusicCollectionHeader(title: title, subtitle: subtitle, artworkURL: artwork, tracks: tracks,
                description: String(localized: "ios-offline-songs-only"))
            ForEach(tracks) { track in
                TrackRow(track: track) { playback.play(track, in: tracks, source: title) }
                    .swipeActions { Button("ios-remove-download", role: .destructive) { downloads.remove(track.id) } }
            }
        }.listStyle(.plain).navigationBarTitleDisplayMode(.inline)
        .appNavigationTitle("").collectionArtworkTheme(artwork)
    }
}

struct DownloadedCollectionLabel: View {
    let title: String
    let subtitle: String
    let artwork: URL?
    var body: some View {
        HStack(spacing: Layout.spacing) {
            ArtworkView(url: artwork, side: Layout.rowArtwork)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(title).appFont(.body).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}
