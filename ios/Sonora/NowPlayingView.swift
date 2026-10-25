import AVKit
import MediaPlayer
import SwiftUI

/// The system tab accessory automatically moves with the Liquid Glass tab bar and pops up into Now Playing on tap or upward swipe.
struct MiniPlayer: View {
    @Environment(PlaybackController.self) private var playback
    let open: () -> Void

    var body: some View {
        HStack(spacing: Layout.compact) {
            Button(action: open) {
                HStack(spacing: Layout.compact + 2) {
                    ArtworkView(track: playback.current, side: Layout.miniArtwork, cornerRadius: 8)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(playback.current?.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if playback.current?.explicit == true {
                                Image(systemName: "e.square.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(playback.current?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
                    if playback.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                    }
                }
                .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))

            Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-next"))
        }
        .padding(.horizontal, Layout.compact + 4)
        .gesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    if value.translation.height < -16 {
                        open()
                    }
                }
        )
    }
}

/// Full-screen Apple Music-style Now Playing sheet with scaling artwork, inline synced lyrics, and inline Up Next queue.
struct NowPlayingView: View {
    private enum Mode: Hashable { case artwork, lyrics, queue }
    private enum QueueListMode: Hashable { case upNext, history }

    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var mode: Mode = .artwork
    @State private var queueMode: QueueListMode = .upNext
    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var lyrics = LyricsStore()

    init(initialMode: String = "artwork") {
        _mode = State(initialValue: initialMode == "lyrics" ? .lyrics : (initialMode == "queue" ? .queue : .artwork))
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, min(geometry.size.width - Layout.playerMargin * 2,
                           max(Layout.playerMinimumArtwork, geometry.size.height - Layout.playerChrome)))
            ZStack {
                if textSize.isAccessibilitySize {
                    ScrollView {
                        playerContent(artworkSide: min(side, Layout.accessibleArtwork), expands: false)
                    }
                } else {
                    playerContent(artworkSide: side, expands: true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            GeometryReader { geometry in
                atmosphericBackground
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sensoryFeedback(.selection, trigger: mode)
        .onAppear { loadLyricsIfNeeded() }
        .onChange(of: playback.current?.id) { _, _ in loadLyricsIfNeeded() }
        .onDisappear { lyrics.cancel() }
    }

    /// Keeps the artwork and every control within the sheet, even with accessibility text sizes.
    private func playerContent(artworkSide: CGFloat, expands: Bool) -> some View {
        VStack(spacing: Layout.playerSpacing) {
            grabberHeader
            if let error = playback.error { errorBanner(error) }
            Group {
                switch mode {
                case .artwork: artworkStage(side: artworkSide)
                case .lyrics: lyricsStage
                case .queue: queueStage
                }
            }
            .frame(maxWidth: .infinity, minHeight: expands ? nil : Layout.accessibleArtwork,
                   maxHeight: expands ? .infinity : nil)
            scrubberSection.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            transportControls.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            volumeSection.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            bottomModeBar.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.horizontal, Layout.playerMargin)
        .padding(.top, Layout.compact)
        .padding(.bottom, Layout.spacing)
    }

    private var atmosphericBackground: some View {
        ZStack {
            Color(red: 0.09, green: 0.09, blue: 0.12)
                .ignoresSafeArea()
            if !reduceTransparency, let url = playback.current?.artworkURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 64)
                        .scaleEffect(1.25)
                } placeholder: {
                    EmptyView()
                }
                .ignoresSafeArea()
            }
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var grabberHeader: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Capsule()
                    .fill(.white.opacity(0.38))
                    .frame(width: 40, height: 5)
                    .frame(width: Layout.control * 1.5, height: Layout.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-done"))
            Spacer()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Layout.compact) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("ios-retry") {
                playback.error = nil
                playback.resume()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.glass)
            Button {
                playback.error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(Layout.compact + 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func artworkStage(side: CGFloat) -> some View {
        VStack(spacing: Layout.spacing * 1.25) {
            Spacer(minLength: 0)
            ArtworkView(track: playback.current, side: side, cornerRadius: Layout.artworkRadius)
                .scaleEffect((playback.isPlaying || !settings.animatedArtwork) ? 1.0 : 0.82)
                .shadow(
                    color: .black.opacity(playback.isPlaying ? 0.50 : 0.25),
                    radius: playback.isPlaying ? 26 : 12,
                    y: playback.isPlaying ? 14 : 6
                )
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: playback.isPlaying)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            trackHeaderRow
        }
    }

    private var trackHeaderRow: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Layout.compact) {
                    trackTitles
                    HStack { favoriteControl; overflowMenu; Spacer() }
                }
            } else {
                HStack(spacing: Layout.compact) {
                    trackTitles
                    Spacer(minLength: Layout.compact)
                    favoriteControl
                    overflowMenu
                }
            }
        }
    }

    private var trackTitles: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text(playback.current?.title ?? "")
                .font(.title2.bold()).foregroundStyle(.white)
                .lineLimit(textSize.isAccessibilitySize ? 3 : 1)
            Text(playback.current?.artist ?? "")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                .lineLimit(textSize.isAccessibilitySize ? 2 : 1)
        }
    }

    @ViewBuilder
    private var favoriteControl: some View {
        if let current = playback.current, current.youtubeID != nil {
            Button { catalog.toggleLike(current) } label: {
                Image(systemName: catalog.isLiked(current) ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(catalog.isLiked(current) ? .yellow : .white.opacity(0.88))
                    .frame(width: Layout.control, height: Layout.control)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityLabel(Text("ios-favorite"))
        }
    }

    private var compactTrackHeader: some View {
        HStack(spacing: Layout.compact + 2) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                    mode = .artwork
                }
            } label: {
                HStack(spacing: Layout.compact + 2) {
                    ArtworkView(track: playback.current, side: 46, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playback.current?.title ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(playback.current?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: Layout.compact)
            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            if let track = playback.current {
                Button("ios-play-next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    playback.playNext(track)
                }
                Button("ios-add-to-queue", systemImage: "text.badge.plus") {
                    playback.addToQueue(track)
                }
                if track.youtubeID != nil {
                    Button("ios-start-radio", systemImage: "dot.radiowaves.left.and.right") {
                        playback.startRadio(for: track)
                    }
                    Button(
                        catalog.isLiked(track) ? "ios-remove-favorite" : "ios-favorite",
                        systemImage: catalog.isLiked(track) ? "star.slash" : "star"
                    ) {
                        catalog.toggleLike(track)
                    }
                    if !catalog.savedPlaylists.filter(\.editable).isEmpty, let videoID = track.youtubeID {
                        Menu("ios-add-to-playlist", systemImage: "music.note.list") {
                            ForEach(catalog.savedPlaylists.filter(\.editable)) { playlist in
                                Button(playlist.title) {
                                    Task { try? await NativeProvider.addPlaylistTrack(playlistID: playlist.id, videoID: videoID) }
                                }
                            }
                        }
                    }
                }
                Button(
                    settings.isPinned(track.id) ? "ios-unpin" : "ios-pin",
                    systemImage: settings.isPinned(track.id) ? "pin.slash" : "pin"
                ) {
                    settings.pinTrack(track)
                }
                if track.youtubeID != nil {
                    if downloads.entry(for: track.id) != nil {
                        Button("ios-remove-download", systemImage: "trash", role: .destructive) {
                            downloads.remove(track.id)
                        }
                    } else {
                        Button("ios-download", systemImage: "arrow.down.circle") {
                            downloads.enqueue(track)
                        }
                    }
                }
            }
            Menu("ios-sleep-timer", systemImage: "moon.zzz") {
                ForEach(SleepTimerOption.allCases) { option in
                    Button {
                        settings.setSleepTimer(option)
                    } label: {
                        HStack {
                            Text(option.labelKey)
                            if settings.sleepTimer == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Menu("ios-equalizer", systemImage: "slider.vertical.3") {
                Toggle("ios-equalizer-enable", isOn: Bindable(settings).equalizerEnabled)
                ForEach(EqualizerPreset.allCases) { preset in
                    Button {
                        settings.equalizerEnabled = true
                        settings.equalizerPreset = preset
                        playback.applyAudioGain()
                    } label: {
                        HStack {
                            Text(preset.labelKey)
                            if settings.equalizerEnabled && settings.equalizerPreset == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: Layout.control, height: Layout.control)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(Text("ios-track-actions"))
    }

    private var lyricsStage: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            compactTrackHeader

            Group {
                if lyrics.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("ios-loading-lyrics")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = lyrics.error {
                    VStack(spacing: Layout.compact) {
                        Spacer()
                        Image(systemName: "quote.bubble")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("ios-lyrics-unavailable")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button("ios-retry") { loadLyricsIfNeeded(force: true) }
                            .buttonStyle(.glass)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if lyrics.sheet?.instrumental == true {
                    VStack(spacing: Layout.compact) {
                        Spacer()
                        Image(systemName: "music.quarternote.3")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("ios-lyrics-instrumental")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if settings.syncedLyrics,
                          let lines = lyrics.sheet?.lines,
                          !lines.isEmpty,
                          lyrics.sheet?.synced == true {
                    syncedLyricsList(lines)
                } else if let text = lyrics.sheet?.text, !text.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Layout.spacing) {
                            Text(text)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let source = lyrics.sheet?.source, !source.isEmpty {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.vertical, Layout.compact)
                    }
                } else {
                    VStack(spacing: Layout.compact) {
                        Spacer()
                        Image(systemName: "quote.bubble")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("ios-lyrics-unavailable")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("ios-no-lyrics-description")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func syncedLyricsList(_ lines: [LyricsLineItem]) -> some View {
        let activeID = activeLyricsLineID(in: lines)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(lines) { line in
                        let isActive = line.id == activeID
                        Button {
                            guard let start = line.start_seconds else { return }
                            playback.seek(to: start)
                            if !playback.isPlaying { playback.resume() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.text)
                                    .font(isActive ? .title2.bold() : .title3.bold())
                                    .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.42))
                                    .blur(radius: (!isActive && settings.blurInactiveLyrics) ? 1.2 : 0)
                                    .multilineTextAlignment(.leading)
                                if settings.romanizedLyrics, let romanized = line.romanized, !romanized.isEmpty {
                                    Text(romanized)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(isActive ? 0.78 : 0.34))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(isActive ? 1.01 : 0.98, anchor: .leading)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isActive)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }
                    if let source = lyrics.sheet?.source, !source.isEmpty {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, Layout.compact)
                    }
                }
                .padding(.vertical, Layout.spacing)
            }
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func activeLyricsLineID(in lines: [LyricsLineItem]) -> Int? {
        let time = playback.elapsed
        if let match = lines.last(where: { $0.start_seconds.map { time >= $0 } ?? false }) {
            return match.id
        }
        return lines.first?.id
    }

    private var queueStage: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: Layout.compact) {
            compactTrackHeader

            HStack(spacing: Layout.compact) {
                queueModePill(
                    symbol: "shuffle",
                    label: "ios-shuffle",
                    isActive: playback.isShuffled,
                    action: playback.toggleShuffle
                )
                queueModePill(
                    symbol: playback.repeatMode.symbol,
                    label: repeatLabel,
                    isActive: playback.repeatMode != .off,
                    action: playback.cycleRepeat
                )
                queueModePill(
                    symbol: "infinity",
                    label: "ios-autoplay-radio",
                    isActive: settings.autoplayRadio,
                    action: { settings.autoplayRadio.toggle() }
                )
            }

            HStack {
                Picker("ios-queue", selection: $queueMode) {
                    Text("ios-playing-next").tag(QueueListMode.upNext)
                    Text("ios-history").tag(QueueListMode.history)
                }
                .pickerStyle(.segmented)

                if queueMode == .upNext && playback.queue.count > 1 {
                    Button("ios-clear") {
                        playback.clearUpcomingQueue()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                } else if queueMode == .history && !settings.history.isEmpty {
                    Button("ios-clear") {
                        settings.clearHistory()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                }
            }

            ScrollView {
                LazyVStack(spacing: Layout.compact) {
                    let tracks = queueMode == .upNext ? playback.queue : settings.history
                    ForEach(tracks) { track in
                        HStack(spacing: Layout.compact + 2) {
                            Button {
                                if queueMode == .upNext {
                                    playback.select(track)
                                } else {
                                    playback.play(track, in: settings.history)
                                }
                            } label: {
                                HStack(spacing: Layout.compact + 2) {
                                    ArtworkView(track: track, side: 42, cornerRadius: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.68))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if playback.current?.id == track.id {
                                        Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if queueMode == .upNext && playback.current?.id != track.id {
                                Button {
                                    playback.removeFromQueue(track)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: Layout.control, height: Layout.control)
                                }
                                .buttonStyle(.plain)
                            } else if queueMode == .history {
                                Button {
                                    settings.removeFromHistory(track)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: Layout.control, height: Layout.control)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func queueModePill(symbol: String, label: LocalizedStringKey, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var scrubberSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekValue : playback.elapsed },
                    set: { seekValue = $0 }
                ),
                in: 0...max(playback.duration, 1),
                onEditingChanged: { editing in
                    if editing { seekValue = playback.elapsed }
                    isSeeking = editing
                    if !editing { playback.seek(to: seekValue) }
                }
            )
            .tint(.white)
            .disabled(playback.duration <= 0)
            .accessibilityLabel(Text("ios-playback-position"))

            HStack {
                Text(time(isSeeking ? seekValue : playback.elapsed))
                Spacer()
                if let badge = qualityBadgeText {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("-" + time(max(0, playback.duration - (isSeeking ? seekValue : playback.elapsed))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.68))
            .accessibilityHidden(true)
        }
    }

    private var qualityBadgeText: String? {
        var parts: [String] = []
        if let badge = playback.streamBadge, !badge.isEmpty {
            parts.append(badge)
        }
        if settings.equalizerEnabled {
            parts.append("EQ")
        }
        if settings.sleepTimer != .off {
            parts.append("ZZZ")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var transportControls: some View {
        HStack(spacing: Layout.spacing * 2.5) {
            Button(action: playback.previous) {
                Image(systemName: "backward.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-previous"))

            Button(action: playback.toggle) {
                Group {
                    if playback.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 68, height: 68)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))

            Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-next"))
        }
    }

    private var volumeSection: some View {
        HStack(spacing: Layout.compact + 2) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            SystemVolumeSlider()
                .frame(height: 24)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var bottomModeBar: some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                    mode = (mode == .lyrics) ? .artwork : .lyrics
                }
            } label: {
                Image(systemName: mode == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(mode == .lyrics ? Color.black : Color.white.opacity(0.82))
                    .frame(width: Layout.control, height: Layout.control)
                    .background(mode == .lyrics ? Color.white : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-lyrics"))

            Spacer()

            AirPlayButton()
                .frame(width: Layout.control, height: Layout.control)

            Spacer()

            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                    mode = (mode == .queue) ? .artwork : .queue
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(mode == .queue ? Color.black : Color.white.opacity(0.82))
                        .frame(width: Layout.control, height: Layout.control)
                        .background(mode == .queue ? Color.white : Color.clear, in: Capsule())
                    if playback.isShuffled || playback.repeatMode != .off {
                        Circle()
                            .fill(mode == .queue ? Color.black : Color.white)
                            .frame(width: 6, height: 6)
                            .offset(x: -6, y: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-queue"))
        }
        .padding(.horizontal, Layout.spacing)
    }

    private var repeatLabel: LocalizedStringKey {
        switch playback.repeatMode {
        case .off: "ios-off"
        case .all: "ios-repeat-all"
        case .one: "ios-repeat-one"
        }
    }

    private func loadLyricsIfNeeded(force: Bool = false) {
        guard let current = playback.current else { return }
        if let id = current.youtubeID {
            lyrics.load(id, title: current.title, artist: current.artist)
        } else if settings.localFileLyrics {
            lyrics.load(current.id, title: current.title, artist: current.artist)
        } else if force {
            lyrics.cancel()
        }
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Native hardware volume slider hosted inside the expanded Apple Music Now Playing screen.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Native route picker hands AirPlay selection and connection state to iOS.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor.white.withAlphaComponent(0.82)
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
