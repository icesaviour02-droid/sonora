import SwiftUI

/// Native multi-selection adds library or downloaded songs without starting playback.
struct QueueSongsPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""

    private var songs: [MusicTrack] {
        var seen = Set<String>()
        return (library.tracks + catalog.likedSongs + downloads.entries.filter { $0.state == .downloaded }.map(\.track))
            .filter { seen.insert($0.id).inserted && $0.available != false }
    }

    var body: some View {
        List(selection: $selected) {
            ForEach(songs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }) { track in
                TrackRow(track: track) {}.selecting().tag(track.id)
                    .accessibilityIdentifier("queue-picker-song-" + track.id)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .searchable(text: $query)
        .navigationTitle("ios-add-songs-to-queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-add") {
                    playback.addToQueue(songs.filter { selected.contains($0.id) })
                    dismiss()
                }.disabled(selected.isEmpty).accessibilityIdentifier("queue-picker-confirm")
            }
        }
        .overlay { if songs.isEmpty { ContentUnavailableView("ios-songs", systemImage: "music.note") } }
    }
}
