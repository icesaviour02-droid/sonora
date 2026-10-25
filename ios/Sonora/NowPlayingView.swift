import AVKit
import SwiftUI

/// The system tab accessory automatically moves with the Liquid Glass tab bar.
struct MiniPlayer: View {
    @Environment(PlaybackController.self) private var playback
    let open: () -> Void

    var body: some View {
        HStack(spacing: Layout.compact) {
            Button(action: open) {
                HStack(spacing: Layout.spacing) {
                    Image(systemName: "music.note").accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(playback.current?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(playback.current?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("ios-open-player"))
            Button(action: playback.toggle) {
                Group {
                    if playback.isLoading { ProgressView() }
                    else { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                }.frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))
        }
        .padding(.horizontal, Layout.spacing)
    }
}

struct NowPlayingView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.spacing * 2) {
                    ArtworkView(track: playback.current, side: Layout.artwork)
                        .accessibilityHidden(true)
                    VStack(spacing: Layout.compact) {
                        Text(playback.current?.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(playback.current?.artist ?? "").foregroundStyle(.secondary)
                    }
                    VStack {
                        Slider(value: Binding(
                            get: { isSeeking ? seekValue : playback.elapsed },
                            set: { seekValue = $0 }
                        ), in: 0...max(playback.duration, 1), onEditingChanged: { editing in
                            if editing { seekValue = playback.elapsed }
                            isSeeking = editing
                            if !editing { playback.seek(to: seekValue) }
                        })
                        .disabled(playback.duration <= 0)
                        .accessibilityLabel(Text("ios-playback-position"))
                        HStack {
                            Text(time(playback.elapsed))
                            Spacer()
                            Text(time(playback.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                    HStack(spacing: Layout.spacing) {
                        transport("backward.fill", label: "ios-previous", action: playback.previous)
                        Button(action: playback.toggle) {
                            Group {
                                if playback.isLoading { ProgressView() }
                                else { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title) }
                            }.frame(minWidth: Layout.control * 1.5, minHeight: Layout.control * 1.5)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))
                        transport("forward.fill", label: "ios-next") { playback.next() }
                    }
                    HStack(spacing: Layout.spacing) {
                        Button(action: playback.toggleShuffle) {
                            Image(systemName: "shuffle").frame(minWidth: Layout.control, minHeight: Layout.control)
                        }
                        .buttonStyle(.glass)
                        .tint(playback.isShuffled ? .accentColor : .primary)
                        .accessibilityLabel(Text("ios-shuffle"))
                        .accessibilityValue(Text(playback.isShuffled ? LocalizedStringKey("ios-on") : LocalizedStringKey("ios-off")))
                        AirPlayButton().frame(width: Layout.control, height: Layout.control)
                        Button(action: playback.cycleRepeat) {
                            Image(systemName: playback.repeatMode.symbol).frame(minWidth: Layout.control, minHeight: Layout.control)
                        }
                        .buttonStyle(.glass)
                        .tint(playback.repeatMode == .off ? .primary : .accentColor)
                        .accessibilityLabel(Text("ios-repeat"))
                        .accessibilityValue(Text(repeatLabel))
                        Button("ios-queue", systemImage: "list.bullet") { showQueue = true }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Layout.control, minHeight: Layout.control)
                            .buttonStyle(.glass)
                    }
                }
                .padding(Layout.spacing * 1.5)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ios-now-playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ios-done") { dismiss() } } }
            .sheet(isPresented: $showQueue) { QueueView() }
        }
        .presentationDragIndicator(.visible)
    }

    private var repeatLabel: LocalizedStringKey {
        switch playback.repeatMode {
        case .off: "ios-off"
        case .all: "ios-repeat-all"
        case .one: "ios-repeat-one"
        }
    }

    private func transport(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).frame(minWidth: Layout.control, minHeight: Layout.control)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(label))
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct QueueView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(playback.queue) { track in
                TrackRow(track: track) { playback.select(track) }
            }
            .navigationTitle("ios-queue")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ios-done") { dismiss() } } }
        }
    }
}

/// Native route picker hands AirPlay selection and connection state to iOS.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
