import SwiftUI
import UniformTypeIdentifiers

/// System tabs supply the native floating Liquid Glass navigation on iOS 26.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showPlayer = false

    var body: some View {
        TabView {
            Tab("ios-library", systemImage: "music.note.house") {
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
            Tab("ios-downloads", systemImage: "arrow.down.circle") {
                NavigationStack { DownloadsView() }
            }
            Tab("ios-search", systemImage: "magnifyingglass", role: .search) {
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
    }
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
    @State private var query = ""

    private var matches: [LocalTrack] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return library.tracks.filter {
            $0.title.localizedStandardContains(term) || $0.artist.localizedStandardContains(term)
        }
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("ios-search-library", systemImage: "magnifyingglass", description: Text("ios-search-description"))
                    .modifier(ScrollableEmptyState())
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .modifier(ScrollableEmptyState())
            } else {
                List(matches) { track in
                    TrackRow(track: track) { playback.play(track, in: matches) }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("ios-search")
        .searchable(text: $query, prompt: "ios-search-prompt")
    }
}

struct DownloadsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("ios-downloads-empty", systemImage: "arrow.down.circle")
        } description: {
            Text("ios-downloads-description")
        }
        .modifier(ScrollableEmptyState())
        .navigationTitle("ios-downloads")
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("ios-music-service") {
                    LabeledContent("ios-youtube-music", value: String(localized: "ios-in-development"))
                    Text("ios-service-description").foregroundStyle(.secondary)
                }
                Section("ios-about") {
                    LabeledContent("ios-version", value: "0.1.0")
                    Text("ios-license").foregroundStyle(.secondary)
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
    let track: LocalTrack
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.spacing) {
                Image(systemName: "music.note")
                    .frame(width: Layout.control, height: Layout.control)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: Layout.compact))
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
        }
        .buttonStyle(.plain)
    }
}
