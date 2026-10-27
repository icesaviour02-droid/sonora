import AVKit
import MediaPlayer
import SwiftUI

/// The system tab accessory automatically moves with the Liquid Glass tab bar and pops up into Now Playing on tap or upward swipe.
struct MiniPlayer: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let open: () -> Void

    var body: some View {
        HStack(spacing: Layout.compact) {
            Button(action: open) {
                HStack(spacing: Layout.compact + 2) {
                    ArtworkView(track: playback.current,
                        side: placement == .inline ? Layout.inlineMiniArtwork : Layout.miniArtwork,
                        cornerRadius: Layout.miniArtworkRadius)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            FadingText(playback.current?.title ?? "", style: .callout, weight: .semibold)
                            if playback.current?.explicit == true {
                                Image(systemName: "e.square.fill")
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        FadingText(playback.current?.artist ?? "", style: .subheadline, color: .label)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(playback.current?.title ?? "") + Text(", ") + Text(playback.current?.artist ?? ""))
            .accessibilityHint(Text("ios-open-player"))
            .accessibilityIdentifier("mini-player-open")

            Button(action: playback.toggle) {
                Group {
                    if playback.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .appFont(.title3, weight: .semibold)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    }
                }
                .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))

            if placement == .expanded { Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .appFont(.body, weight: .semibold)
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-next"))
            }
        }
        .padding(.horizontal, Layout.spacing)
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

    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var mode: Mode = .artwork
    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var lyrics = LyricsStore()
    @State private var chooseLocalPlaylist = false
    @State private var addQueueSongs = false
    @State private var queueHeaderOffset: CGFloat = 0
    @State private var queueHeaderHeight: CGFloat = Layout.queueHeaderArtwork + Layout.queueModeHeight + Layout.spacing * 2
    @State private var trackHeaderHeight: CGFloat = Layout.playerTitleReserve
    @State private var artworkFrame: CGRect = .zero
    @State private var artworkMode: Mode = .artwork
    @State private var artworkWasPlaying = false
    @Namespace private var playerElements

    init(initialMode: String = "artwork") {
        _mode = State(initialValue: initialMode == "lyrics" ? .lyrics : (initialMode == "queue" ? .queue : .artwork))
    }

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, geometry.size.width - Layout.playerMargin * 2)
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
        .onChange(of: settings.localFileLyrics) { _, _ in loadLyricsIfNeeded() }
        .onChange(of: settings.lyricsSources) { _, _ in loadLyricsIfNeeded() }
        .onChange(of: mode) { _, _ in loadLyricsIfNeeded() }
        .onDisappear { lyrics.cancel() }
        .sheet(isPresented: $addQueueSongs) {
            NavigationStack { QueueSongsPicker() }
        }
        .sheet(isPresented: $chooseLocalPlaylist) {
            NavigationStack { AddToLocalPlaylistView(trackIDs: playback.current.map { [$0.id] } ?? []) }
        }
    }

    /// Keeps the artwork and every control within the sheet, even with accessibility text sizes.
    private func playerContent(artworkSide: CGFloat, expands: Bool) -> some View {
        VStack(spacing: Layout.playerSpacing) {
            grabberHeader
            if let error = playback.error { errorBanner(error) }
            if mode == .lyrics { compactTrackHeader(presentation: .lyrics).transition(.opacity) }
            Group {
                switch mode {
                case .artwork: artworkStage(side: artworkSide)
                case .lyrics: lyricsStage.transition(.opacity)
                case .queue: queueStage.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: expands ? nil :
                   (mode == .artwork ? Layout.accessibleArtwork + trackHeaderHeight + Layout.spacing : Layout.accessibleArtwork),
                   maxHeight: expands ? .infinity : nil)
            scrubberSection.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            transportControls.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            volumeSection.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            bottomModeBar.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.horizontal, Layout.playerMargin)
        .padding(.top, Layout.compact)
        .padding(.bottom, Layout.spacing)
        .coordinateSpace(name: "player-artwork-space")
        .overlay(alignment: .topLeading) {
            if !artworkFrame.isEmpty {
                // Keep the rendition and view identity unchanged throughout mode changes.
                let renderSide = max(Layout.artwork, artworkSide)
                ArtworkView(track: playback.current, side: renderSide, cornerRadius: 0)
                    .scaleEffect(artworkFrame.width / renderSide, anchor: .topLeading)
                    .frame(width: artworkFrame.width, height: artworkFrame.height, alignment: .topLeading)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: mode == .artwork ? Layout.artworkRadius : Layout.compact))
                    .shadow(color: .black.opacity(mode == .artwork ? 0.3 : 0), radius: Layout.spacing, y: Layout.compact)
                    .position(x: artworkFrame.midX, y: artworkFrame.midY)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onPreferenceChange(PlayerArtworkFrame.self) { target in
            guard !target.isEmpty else { return }
            let animate = !artworkFrame.isEmpty && (artworkMode != mode || artworkWasPlaying != playback.isPlaying)
            artworkMode = mode
            artworkWasPlaying = playback.isPlaying
            if animate && !reduceMotion {
                withAnimation(PlayerMotion.mode) { artworkFrame = target }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { artworkFrame = target }
            }
        }
    }

    /// Invisible geometry targets guide one persistent cover rather than replacing the image.
    private func artworkTarget(side: CGFloat, presentation: Mode) -> some View {
        Color.clear.frame(width: side, height: side)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PlayerArtworkFrame.self,
                        value: mode == presentation ? geometry.frame(in: .named("player-artwork-space")) : .zero)
                }
            }
            .accessibilityHidden(true)
    }

    private var atmosphericBackground: some View {
        ZStack {
            Color(red: 0.09, green: 0.09, blue: 0.12)
                .ignoresSafeArea()
            if !reduceTransparency, let url = playback.current?.displayArtworkURL {
                ArtworkImage(url: url) { image in
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
            .accessibilityIdentifier("player-dismiss")
            Spacer()
        }
        .frame(height: Layout.grabberHeight)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Layout.compact) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .appFont(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("ios-retry") {
                playback.error = nil
                playback.resume()
            }
            .appFont(.caption, weight: .semibold)
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
        GeometryReader { geometry in
            let boundedSide = min(side, max(1, geometry.size.height - trackHeaderHeight - Layout.spacing))
            VStack(spacing: Layout.spacing) {
                ZStack {
                    artworkTarget(side: boundedSide * ((playback.isPlaying || !settings.animatedArtwork) ? 1 : 0.82), presentation: .artwork)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                trackHeaderRow
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height > 0 { trackHeaderHeight = height }
                    }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
                .appFont(.title2, weight: .bold).foregroundStyle(.white)
                .lineLimit(textSize.isAccessibilitySize ? 3 : 1)
            Text(playback.current?.artist ?? "")
                .appFont(.subheadline).foregroundStyle(.white.opacity(0.75))
                .lineLimit(textSize.isAccessibilitySize ? 2 : 1)
        }
        .matchedGeometryEffect(id: "metadata", in: playerElements, isSource: mode == .artwork)
    }

    @ViewBuilder
    private var favoriteControl: some View {
        if let current = playback.current {
            let favorite = current.youtubeID != nil ? catalog.isLiked(current) : localLibrary.favoriteTracks.contains(current.id)
            Button {
                if current.youtubeID != nil { catalog.toggleLike(current) }
                else { localLibrary.toggleFavorite(current.id, category: .tracks) }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: Layout.control, height: Layout.control)
                    .background(mode == .artwork ? .white.opacity(0.14) : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .disabled(current.youtubeID == nil && (localLibrary.isBusy || !localLibrary.isLoaded))
            .accessibilityLabel(Text(favorite ? "ios-remove-favorite" : "ios-favorite"))
        }
    }

    private func compactTrackHeader(presentation: Mode) -> some View {
        HStack(spacing: Layout.compact + 2) {
            Button {
                changeMode(.artwork)
            } label: {
                HStack(spacing: Layout.spacing - Layout.compact / 2) {
                    artworkTarget(side: Layout.queueHeaderArtwork, presentation: presentation)
                    VStack(alignment: .leading, spacing: 2) {
                        FadingText(playback.current?.title ?? "", style: .body, weight: .semibold)
                        FadingText(playback.current?.artist ?? "", style: .body, color: .secondaryLabel)
                    }
                    .matchedGeometryEffect(id: "metadata", in: playerElements, isSource: mode != .artwork)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(playback.current?.title ?? "") + Text(", ") + Text(playback.current?.artist ?? ""))
            .accessibilityHint(Text("ios-open-player"))
            .accessibilityIdentifier("player-return-artwork")
            favoriteControl
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
                if track.youtubeID == nil {
                    LocalTrackActions(track: track) { chooseLocalPlaylist = true }
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
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: Layout.control, height: Layout.control)
                .background(mode == .artwork ? .white.opacity(0.14) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(Text("ios-track-actions"))
        .accessibilityIdentifier("player-more")
    }

    private var lyricsStage: some View {
        LyricsContentView(store: lyrics, retry: loadLyricsIfNeeded)
    }

    /// Keeps the matched artwork in the same SwiftUI scene while UIKit scrolls history and rows.
    private var queueStage: some View {
        ZStack(alignment: .top) {
            NativeQueueList(upcoming: playback.upcomingItems, history: settings.history,
                autoplay: settings.autoplayRadio, playback: playback, settings: settings,
                headerHeight: queueHeaderHeight,
                headerOffset: { offset in
                    DispatchQueue.main.async {
                        if abs(queueHeaderOffset - offset) > 0.5 {
                            let delta = offset - queueHeaderOffset
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                queueHeaderOffset = offset
                                if mode == .queue && !artworkFrame.isEmpty { artworkFrame.origin.y += delta }
                            }
                        }
                    }
                }, addSongs: { addQueueSongs = true })
            VStack(spacing: Layout.spacing) {
                compactTrackHeader(presentation: .queue)
                HStack(spacing: Layout.compact) {
                    queueModePill(symbol: "shuffle", label: "ios-shuffle", isActive: playback.isShuffled,
                        action: playback.toggleShuffle)
                    queueModePill(symbol: playback.repeatMode.symbol, label: repeatLabel,
                        isActive: playback.repeatMode != .off, action: playback.cycleRepeat)
                    queueModePill(symbol: "infinity", label: "ios-autoplay-radio", isActive: settings.autoplayRadio,
                        action: { settings.autoplayRadio.toggle() })
                }
            }
            .padding(.bottom, Layout.spacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { queueHeaderHeight = $0 }
            .offset(y: queueHeaderOffset)
        }
        .clipped()
        .mask(alignment: .bottom) {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.queueFade)
            }
        }
    }

    private func queueModePill(symbol: String, label: LocalizedStringKey, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(isActive ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: Layout.queueModeHeight)
                .background(
                    isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14)),
                    in: Capsule()
                )
        }
        .buttonStyle(PlayerControlStyle())
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(Text(label))
    }

    private var scrubberSection: some View {
        VStack(spacing: 4) {
            MusicSeekSlider(
                value: Binding(
                    get: { isSeeking ? seekValue : playback.elapsed },
                    set: { seekValue = $0 }
                ),
                range: 0...max(playback.duration, 1),
                onEditingChanged: { editing in
                    if editing { seekValue = playback.elapsed }
                    isSeeking = editing
                    if !editing { playback.seek(to: seekValue) }
                }
            )
            .frame(height: Layout.control)
            .disabled(playback.duration <= 0)
            .accessibilityLabel(Text("ios-playback-position"))

            HStack {
                Text(time(isSeeking ? seekValue : playback.elapsed))
                Spacer()
                if let badge = qualityBadgeText {
                    Text(badge)
                        .appFont(.caption2, weight: .semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("-" + time(max(0, playback.duration - (isSeeking ? seekValue : playback.elapsed))))
            }
            .appFont(.caption).monospacedDigit()
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
        HStack(spacing: 0) {
            Button(action: playback.previous) {
                Image(systemName: "backward.fill")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text("ios-previous"))

            Spacer(minLength: Layout.compact)

            Button(action: playback.toggle) {
                Group {
                    if playback.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 68, height: 68)
            }
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text((playback.isPlaying || playback.isLoading) ? LocalizedStringKey("ios-pause") : LocalizedStringKey("ios-play")))

            Spacer(minLength: Layout.compact)

            Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text("ios-next"))
        }
        .padding(.horizontal, Layout.spacing)
        .frame(height: mode == .artwork ? Layout.control + Layout.playerMargin : Layout.transportHeight)
    }

    private var volumeSection: some View {
        HStack(spacing: Layout.compact + 2) {
            Image(systemName: "speaker.fill")
                .appFont(.caption)
                .foregroundStyle(.white.opacity(0.62))
            SystemVolumeSlider()
                .frame(height: 24)
            Image(systemName: "speaker.wave.3.fill")
                .appFont(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var bottomModeBar: some View {
        HStack {
            Button {
                changeMode(mode == .lyrics ? .artwork : .lyrics)
            } label: {
                Image(systemName: mode == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(mode == .lyrics ? Color.black : Color.white.opacity(0.82))
                    .frame(width: Layout.control, height: Layout.control)
                    .background(mode == .lyrics ? Color.white : Color.clear, in: Capsule())
            }
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text("ios-lyrics"))
            .accessibilityIdentifier("player-lyrics")
            .accessibilityAddTraits(mode == .lyrics ? .isSelected : [])

            Spacer()

            AirPlayButton()
                .frame(width: Layout.control, height: Layout.control)

            Spacer()

            Button {
                changeMode(mode == .queue ? .artwork : .queue)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .appFont(.title3, weight: .semibold)
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
            .buttonStyle(PlayerControlStyle())
            .accessibilityLabel(Text("ios-queue"))
            .accessibilityIdentifier("player-queue")
            .accessibilityAddTraits(mode == .queue ? .isSelected : [])
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

    /// Each opening begins at the current song; a previous history scroll cannot move the cover target.
    private func changeMode(_ next: Mode) {
        withAnimation(reduceMotion ? nil : PlayerMotion.mode) {
            if next == .queue && mode != .queue { queueHeaderOffset = 0 }
            mode = next
        }
    }

    private func loadLyricsIfNeeded() {
        guard let current = playback.current else { lyrics.clear(); return }
        guard mode == .lyrics else { lyrics.cancel(); return }
        guard current.youtubeID != nil || settings.localFileLyrics else { lyrics.clear(); return }
        lyrics.load(current.youtubeID, title: current.title, artist: current.artist,
            album: current.albumTitle, duration: current.durationSeconds,
            sources: settings.enabledLyricsSources, cacheID: current.id)
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
        view.setVolumeThumbImage(PlayerSliderImages.idleThumb, for: .normal)
        view.setVolumeThumbImage(PlayerSliderImages.trackingThumb, for: .highlighted)
        view.setMinimumVolumeSliderImage(PlayerSliderImages.track(alpha: 0.6), for: .normal)
        view.setMaximumVolumeSliderImage(PlayerSliderImages.track(alpha: 0.2), for: .normal)
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

/// The active presentation contributes its cover bounds; empty transition passes keep the old image.
private struct PlayerArtworkFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}
