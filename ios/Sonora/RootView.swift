import SwiftUI
import UniformTypeIdentifiers

/// System tabs supply the native floating Liquid Glass navigation on iOS 26.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSearch.self) private var youtube
    @Environment(DownloadsStore.self) private var downloads
    @State private var selectedTab = Destination.library
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showPlayer = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("ios-library", systemImage: "music.note.house", value: Destination.library) {
                NavigationStack {
                    LibraryView(importAction: { showImporter = true })
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("ios-settings", systemImage: "gearshape") { showSettings = true }
                                    .frame(minWidth: Layout.control, minHeight: Layout.control)
                            }
                        }
                }
            }
            Tab("ios-downloads", systemImage: "arrow.down.circle", value: Destination.downloads) {
                NavigationStack { DownloadsView() }
            }
            Tab("ios-search", systemImage: "magnifyingglass", value: Destination.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessory(open: { showPlayer = true }))
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure: library.error = String(localized: "ios-import-error")
            }
        }
        .alert("ios-error-title", isPresented: Binding(
            get: { library.error != nil || playback.error != nil },
            set: { if !$0 { library.error = nil; playback.error = nil } }
        )) {
            Button("ios-done", role: .cancel) { library.error = nil; playback.error = nil }
        } message: { Text(library.error ?? playback.error ?? "") }
        .onChange(of: library.isLoaded) { _, loaded in
            if loaded { playback.synchronizeLibrary(with: library.tracks) }
        }
        .onChange(of: library.tracks) { _, tracks in
            if library.isLoaded { playback.synchronizeLibrary(with: tracks) }
        }
        .onOpenURL { url in
            guard url.scheme == "sonora",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            let parameters = components.queryItems ?? []
            func value(_ name: String) -> String? { parameters.first { $0.name == name }?.value }
            if url.host == "search", let query = value("q"), !query.isEmpty, query.utf8.count <= 512 {
                youtube.query = query
                selectedTab = .search
                youtube.submit(query)
            } else if let id = value("id"), id.utf8.count == 11,
                      id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) {
                let track = youtube.tracks.first { $0.youtubeID == id } ?? MusicTrack(
                    id: "youtube:" + id,
                    title: String((value("title") ?? id).prefix(200)),
                    artist: String((value("artist") ?? "").prefix(200)),
                    filename: "", addedAt: .now, youtubeID: id
                )
                if url.host == "play" {
                    playback.play(track, in: [track])
                    showPlayer = true
                } else if url.host == "download" {
                    downloads.enqueue(track)
                    selectedTab = .downloads
                }
            }
        }
    }

    private enum Destination: Hashable { case library, downloads, search }
}

/// iOS 26.1 can hide the accessory without rebuilding the tab hierarchy. The 26.0 fallback
/// omits the modifier altogether, since an empty accessory still reserves a glass capsule.
private struct PlayerAccessory: ViewModifier {
    @Environment(PlaybackController.self) private var playback
    let open: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: playback.current != nil) { MiniPlayer(open: open) }
        } else if playback.current != nil {
            content.tabViewBottomAccessory { MiniPlayer(open: open) }
        } else {
            content
        }
    }
}

/// Centers short native empty states, while letting large accessibility text scroll above
/// the safe area instead of pushing actions underneath the tab bar.
private struct ScrollableEmptyState: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    let importAction: () -> Void

    var body: some View {
        Group {
            if !library.isLoaded {
                ContentUnavailableView {
                    Label("ios-library", systemImage: "music.note")
                } description: {
                    Text("ios-loading-library")
                } actions: {
                    Button("ios-retry") { Task { await library.load() } }
                }
                .modifier(ScrollableEmptyState())
            } else if library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("ios-your-music", systemImage: "music.note")
                } description: {
                    Text("ios-import-description")
                } actions: {
                    Button("ios-import", systemImage: "plus", action: importAction)
                        .buttonStyle(.glassProminent)
                }
                .modifier(ScrollableEmptyState())
            } else {
                List {
                    ForEach(library.tracks) { track in
                        TrackRow(track: track) { playback.play(track, in: library.tracks) }
                            .swipeActions {
                                Button("ios-delete", role: .destructive) {
                                    Task { await library.remove(track) }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("ios-library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios-import", systemImage: "plus", action: importAction)
                    .disabled(library.isImporting || !library.isLoaded)
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
        }
        .overlay(alignment: .bottom) {
            if library.isImporting {
                ProgressView("ios-importing")
                    .padding(Layout.spacing)
                    .glassEffect()
                    .padding()
            }
        }
    }
}

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSearch.self) private var youtube
    @State private var scope = Scope.youtube

    private var matches: [MusicTrack] {
        let term = youtube.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return library.tracks.filter {
            $0.title.localizedStandardContains(term) || $0.artist.localizedStandardContains(term)
        }
    }

    var body: some View {
        @Bindable var youtube = youtube
        VStack(spacing: 0) {
            Picker("ios-search-in", selection: $scope) {
                Text("ios-youtube-music").tag(Scope.youtube)
                Text("ios-library").tag(Scope.library)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Layout.spacing)
            .padding(.bottom, Layout.compact)
            Group {
                if scope == .youtube {
                    providerResults
                } else if youtube.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("ios-search-library", systemImage: "magnifyingglass", description: Text("ios-search-description"))
                        .modifier(ScrollableEmptyState())
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: youtube.query)
                        .modifier(ScrollableEmptyState())
                } else {
                    List(matches) { track in
                        TrackRow(track: track) { playback.play(track, in: matches) }
                    }.listStyle(.plain)
                }
            }
        }
        .navigationTitle("ios-search")
        .searchable(text: $youtube.query, prompt: "ios-search-prompt")
        .onSubmit(of: .search) { if scope == .youtube { youtube.submit(youtube.query) } }
        .onChange(of: youtube.query) { _, value in if value.isEmpty { youtube.clear() } }
    }

    @ViewBuilder
    private var providerResults: some View {
        if youtube.isLoading {
            ProgressView("ios-searching")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = youtube.error {
            ContentUnavailableView {
                Label("ios-search-unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("ios-retry") { youtube.submit(youtube.query) }.buttonStyle(.glass)
            }
            .modifier(ScrollableEmptyState())
        } else if !youtube.hasSearched {
            ContentUnavailableView("ios-search-youtube", systemImage: "magnifyingglass", description: Text("ios-search-youtube-description"))
                .modifier(ScrollableEmptyState())
        } else if youtube.tracks.isEmpty {
            ContentUnavailableView.search(text: youtube.query).modifier(ScrollableEmptyState())
        } else {
            List(youtube.tracks) { track in
                TrackRow(track: track) { playback.play(track, in: youtube.tracks) }
                    .disabled(track.available == false)
            }.listStyle(.plain)
        }
    }

    private enum Scope: Hashable { case youtube, library }
}

struct DownloadsView: View {
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        Group {
            if downloads.isRestoring {
                ProgressView("ios-restoring-downloads")
            } else if downloads.entries.isEmpty {
                ContentUnavailableView {
                    Label("ios-downloads-empty", systemImage: "arrow.down.circle")
                } description: {
                    Text(downloads.error ?? String(localized: "ios-downloads-description"))
                }.modifier(ScrollableEmptyState())
            } else {
                List {
                    if let error = downloads.error { Text(error).foregroundStyle(.secondary) }
                    ForEach(downloads.entries) { entry in
                        VStack(alignment: .leading, spacing: Layout.compact) {
                            TrackRow(track: entry.track) {
                                let tracks = downloads.entries.filter { $0.state == .downloaded }.map(\.track)
                                playback.play(entry.track, in: tracks)
                            }
                            .disabled(entry.state != .downloaded)
                            if entry.state == .downloading {
                                ProgressView(value: entry.progress).accessibilityLabel(Text("ios-download-progress"))
                            }
                            HStack {
                                Text(stateLabel(entry.state)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if entry.state == .failed {
                                    Button("ios-retry") { downloads.retry(entry.id) }.buttonStyle(.glass)
                                }
                            }
                        }
                        .swipeActions {
                            Button("ios-remove-download", role: .destructive) { downloads.remove(entry.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("ios-downloads")
    }

    private func stateLabel(_ state: DownloadEntry.State) -> LocalizedStringKey {
        switch state {
        case .queued: "ios-download-queued"
        case .resolving: "ios-download-preparing"
        case .downloading: "ios-downloading"
        case .downloaded: "ios-downloaded"
        case .failed: "ios-download-failed"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadsStore.self) private var downloads

    var body: some View {
        @Bindable var downloads = downloads
        NavigationStack {
            List {
                Section("ios-music-service") {
                    LabeledContent("ios-youtube-music", value: String(localized: "ios-guest-mode"))
                    Text("ios-service-description").foregroundStyle(.secondary)
                }
                Section("ios-about") {
                    LabeledContent("ios-version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("ios-license").foregroundStyle(.secondary)
                }
                Section {
                    Toggle("ios-cellular-downloads", isOn: $downloads.allowsCellular)
                } footer: {
                    Text("ios-cellular-downloads-description")
                }
            }
            .navigationTitle("ios-settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ios-done") { dismiss() } } }
        }
    }
}

/// Full-width native row; the content remains visually separate from the glass navigation layer.
struct TrackRow: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    let track: MusicTrack
    let action: () -> Void

    var body: some View {
        HStack(spacing: Layout.compact) {
            Button(action: action) {
                HStack(spacing: Layout.spacing) {
                ArtworkView(track: track, side: Layout.control)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(track.title).foregroundStyle(.primary).lineLimit(2)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Layout.compact)
                if playback.current?.id == track.id {
                    Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("ios-current-track"))
                }
                }
                .frame(minHeight: Layout.control)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if track.youtubeID != nil {
                Menu {
                    if let entry = downloads.entry(for: track.id) {
                        if entry.state == .failed {
                            Button("ios-retry", systemImage: "arrow.clockwise") { downloads.retry(track.id) }
                        }
                        Button("ios-remove-download", systemImage: "trash", role: .destructive) { downloads.remove(track.id) }
                    } else {
                        Button("ios-download", systemImage: "arrow.down.circle") { downloads.enqueue(track) }
                    }
                } label: {
                    Image(systemName: downloads.entry(for: track.id)?.state == .downloaded ? "checkmark.circle" : "ellipsis")
                        .frame(minWidth: Layout.control, minHeight: Layout.control)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("ios-track-actions"))
            }
        }
    }
}

/// Uses the same square artwork treatment for rows and the expanded player.
struct ArtworkView: View {
    let track: MusicTrack?
    let side: CGFloat

    var body: some View {
        AsyncImage(url: track?.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "music.note").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Layout.compact))
    }
}
