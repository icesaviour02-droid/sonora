import SwiftUI

/// Album and playlist pages share one responsive artwork, title and transport layout.
struct MusicCollectionHeader: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let tracks: [MusicTrack]
    var description: String? = nil
    var symbol = "music.note.list"
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            GeometryReader { geometry in
                cover(side: min(geometry.size.width, Layout.collectionArtwork))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: Layout.collectionArtwork)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(title).appFont(.title2, weight: .bold).fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty { Text(subtitle).appFont(.body).foregroundStyle(.secondary) }
                if let description, !description.isEmpty {
                    Text(description).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            CollectionPlayShuffleHeader(
                playAction: { if let first = tracks.first { playback.play(first, in: tracks) } },
                shuffleAction: { playback.playShuffled(tracks) })
                .disabled(tracks.isEmpty)
        }
        .padding(.vertical, Layout.spacing)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func cover(side: CGFloat) -> some View {
        ArtworkView(url: artworkURL, side: side, cornerRadius: Layout.artworkRadius)
            .placeholderSymbol(symbol)
            .shadow(color: .black.opacity(0.12), radius: Layout.compact, y: Layout.compact / 2)
            .accessibilityHidden(true)
    }
}
