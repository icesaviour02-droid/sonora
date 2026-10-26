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
    @Environment(PlaybackController.self) private var playback
    let albumID: String
    private var album: LocalAlbum? { LocalAlbum.collect(library.tracks).first { $0.id == albumID } }

    var body: some View {
        Group {
            if let album {
                List {
                    VStack(spacing: Layout.spacing) {
                        ArtworkView(track: album.tracks.first { $0.displayArtworkURL != nil } ?? album.tracks.first,
                                    side: Layout.detailArtwork, cornerRadius: Layout.artworkRadius)
                        Text(album.title).appFont(.title2, weight: .bold).multilineTextAlignment(.center)
                        Text(album.artist).appFont(.title3).foregroundStyle(.secondary)
                        HStack(spacing: Layout.spacing) {
                            Button("ios-play", systemImage: "play.fill") { playback.play(album.tracks[0], in: album.tracks) }
                                .buttonStyle(.glassProminent)
                            Button("ios-shuffle", systemImage: "shuffle") { playback.playShuffled(album.tracks) }
                                .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    ForEach(album.tracks) { track in
                        TrackRow(track: track) { playback.play(track, in: album.tracks) }
                    }
                }
                .listStyle(.plain)
            } else { ContentUnavailableView("ios-albums", systemImage: "square.stack") }
        }
        .navigationTitle(album?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
