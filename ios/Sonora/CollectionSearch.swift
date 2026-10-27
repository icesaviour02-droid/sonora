import SwiftUI

/// Page search uses native drawer placement so the pill is revealed by pulling down at the top.
extension View {
    func collectionSearch(text: Binding<String>) -> some View {
        searchable(text: text, placement: .navigationBarDrawer, prompt: Text("ios-search"))
            .scrollDismissesKeyboard(.interactively)
    }
}

/// Matches every query word across the page's actual metadata, with locale-aware accent folding.
enum MusicSearch {
    static func matches(_ query: String, _ fields: String?...) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = fields.compactMap { $0 }.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return words.allSatisfy { text.contains(String($0)) }
    }
}

extension MusicTrack {
    func matchesSearch(_ query: String) -> Bool { MusicSearch.matches(query, title, artist, albumTitle, albumArtist) }
}

/// Root Library and Downloaded search show real cached entities across all their category pages.
struct MusicPageSearchResults: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var local
    @Environment(CatalogStore.self) private var catalog
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback
    let query: String
    var offlineOnly = false

    private var sourceTracks: [MusicTrack] { offlineOnly ? downloads.completedTracks : library.tracks }
    private var songs: [MusicTrack] {
        var seen: Set<String> = []
        let candidates = offlineOnly ? sourceTracks : sourceTracks + catalog.likedSongs + downloads.completedTracks
        return candidates.filter { seen.insert($0.id).inserted && $0.matchesSearch(query) }
    }
    private var albums: [LocalAlbum] {
        LocalAlbum.collect(sourceTracks).filter { MusicSearch.matches(query, $0.title, $0.artist) }
    }
    private var artists: [String] {
        Array(Set(sourceTracks.map(\.artist))).filter { MusicSearch.matches(query, $0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var localPlaylists: [LocalPlaylist] {
        offlineOnly ? [] : local.playlists.filter { MusicSearch.matches(query, $0.title) }
    }
    private var offlinePlaylists: [DownloadedPlaylist] {
        offlineOnly ? downloads.playlists.filter { MusicSearch.matches(query, $0.title, $0.author) } : []
    }
    private var remoteAlbums: [CatalogAlbum] {
        offlineOnly ? [] : catalog.savedAlbums.filter { MusicSearch.matches(query, $0.title, $0.artist) }
    }
    private var remotePlaylists: [CatalogPlaylist] {
        offlineOnly ? [] : catalog.savedPlaylists.filter { MusicSearch.matches(query, $0.title, $0.author) }
    }
    private var remoteArtists: [CatalogArtist] {
        offlineOnly ? [] : catalog.savedArtists.filter { MusicSearch.matches(query, $0.name) }
    }
    private var pending: [DownloadEntry] {
        offlineOnly ? downloads.entries.filter { $0.state != .downloaded && $0.track.matchesSearch(query) } : []
    }
    private var empty: Bool {
        pending.isEmpty && songs.isEmpty && albums.isEmpty && artists.isEmpty && localPlaylists.isEmpty && offlinePlaylists.isEmpty
            && remoteAlbums.isEmpty && remotePlaylists.isEmpty && remoteArtists.isEmpty
    }

    var body: some View {
        List {
            if !pending.isEmpty { Section("ios-downloading") { ForEach(pending) { DownloadTransferRow(entry: $0) } } }
            if !songs.isEmpty {
                Section("ios-songs") {
                    ForEach(songs) { track in TrackRow(track: track) { playback.play(track, in: songs) } }
                }
            }
            if !localPlaylists.isEmpty || !offlinePlaylists.isEmpty || !remotePlaylists.isEmpty {
                Section("ios-playlists") {
                    ForEach(localPlaylists) { playlist in
                        NavigationLink { LocalPlaylistView(playlistID: playlist.id) } label: {
                            LocalPlaylistLabel(playlist: playlist, tracks: playlist.tracks(in: library.tracks))
                        }
                    }
                    ForEach(offlinePlaylists) { playlist in
                        NavigationLink {
                            DownloadedCollectionView(title: playlist.title, subtitle: playlist.author,
                                artwork: playlist.artworkURL, trackIDs: playlist.trackIDs)
                        } label: { DownloadedCollectionLabel(title: playlist.title, subtitle: playlist.author, artwork: playlist.artworkURL) }
                    }
                    ForEach(remotePlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id, fallbackTitle: playlist.title,
                                fallbackAuthor: playlist.author, fallbackArtwork: playlist.artworkURL)
                        } label: { DownloadedCollectionLabel(title: playlist.title, subtitle: playlist.author, artwork: playlist.artworkURL) }
                    }
                }
            }
            if !albums.isEmpty || !remoteAlbums.isEmpty {
                Section("ios-albums") {
                    ForEach(albums) { album in
                        NavigationLink {
                            if offlineOnly {
                                DownloadedCollectionView(title: album.title, subtitle: album.artist,
                                    artwork: album.tracks.first?.displayArtworkURL, trackIDs: album.tracks.map(\.id))
                            } else { LocalAlbumView(albumID: album.id) }
                        } label: { DownloadedCollectionLabel(title: album.title, subtitle: album.artist, artwork: album.tracks.first?.displayArtworkURL) }
                    }
                    ForEach(remoteAlbums) { album in
                        NavigationLink {
                            AlbumDetailView(browseID: album.id, fallbackTitle: album.title,
                                fallbackArtist: album.artist, fallbackArtwork: album.artworkURL)
                        } label: { DownloadedCollectionLabel(title: album.title, subtitle: album.artist, artwork: album.artworkURL) }
                    }
                }
            }
            if !artists.isEmpty || !remoteArtists.isEmpty {
                Section("ios-artists") {
                    ForEach(artists, id: \.self) { name in
                        NavigationLink {
                            if offlineOnly {
                                DownloadedCollectionView(title: name, subtitle: String(localized: "ios-downloaded"), artwork: nil,
                                    trackIDs: sourceTracks.filter { $0.artist == name }.map(\.id))
                            } else { LocalArtistView(name: name) }
                        } label: { Text(name).appFont(.body) }
                    }
                    ForEach(remoteArtists) { artist in
                        NavigationLink {
                            ArtistDetailView(browseID: artist.id, fallbackName: artist.name, fallbackArtwork: artist.artworkURL)
                        } label: { Text(artist.name).appFont(.body) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if empty { ContentUnavailableView.search(text: query) } }
    }
}

extension HomeShelfSection {
    /// Recommendation search keeps real item destinations and omits empty shelves.
    func matchingSearch(_ query: String) -> HomeShelfSection? {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return self }
        let visible = items.filter { MusicSearch.matches(query, $0.title, $0.subtitle) }
        return visible.isEmpty ? nil : HomeShelfSection(id: id, title: title, items: visible)
    }
}
