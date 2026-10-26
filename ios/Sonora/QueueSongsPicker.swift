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
        List {
            ForEach(songs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }) { track in
                Button {
                    if selected.contains(track.id) { selected.remove(track.id) }
                    else { selected.insert(track.id) }
                } label: {
                    HStack(spacing: Layout.compact) {
                        Image(systemName: selected.contains(track.id) ? "checkmark.circle.fill" : "circle")
                            .appFont(.title2)
                            .foregroundStyle(selected.contains(track.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(width: Layout.control, height: Layout.control)
                        TrackRow(track: track) {}.selecting().accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(track.title) + Text(", ") + Text(track.artist))
                .accessibilityAddTraits(selected.contains(track.id) ? .isSelected : [])
                .accessibilityIdentifier("queue-picker-song-" + track.id)
            }
        }
        .listStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
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
