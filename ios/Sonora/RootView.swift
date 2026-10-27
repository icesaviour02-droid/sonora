import SwiftUI
import UniformTypeIdentifiers

/// System tabs supply the native floating Liquid Glass navigation on iOS 26, minimizing on scroll down and expanding on scroll up.
struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSearch.self) private var youtube
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(CatalogStore.self) private var catalog

    @State private var selectedTab = Destination.library
    @State private var showImporter = false
    @State private var showFonts = false
    @State private var showSoundProfiles = false
    @State private var editingSoundProfile: SoundProfile?
    @State private var showSettings = false
    @State private var showPlayer = false
    @State private var playerMode = "artwork"
    @State private var didHandleLaunchURL = false
    @Namespace private var playerTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var guestProbe = GuestAcceptanceProbe()
    @State private var localLyricsProbe = LyricsStore()
    @State private var localLibraryProbe = LocalLibraryReview()
    @State private var localPlaylistPresentation: LocalPlaylistReviewPresentation?
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("ios-home", systemImage: "house.fill", value: Destination.home) {
                NavigationStack {
                    HomeView(openSettings: { showSettings = true })
                }
            }
            Tab("ios-library", systemImage: "square.stack.fill", value: Destination.library) {
                NavigationStack {
                    LibraryView(
                        importAction: { showImporter = true },
                        openSettings: { showSettings = true }
                    )
                }
            }
            Tab("ios-downloads", systemImage: "arrow.down.circle.fill", value: Destination.downloads) {
                NavigationStack {
                    DownloadsView()
                }
            }
            Tab("ios-search", systemImage: "magnifyingglass", value: Destination.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessory(namespace: playerTransition, open: { showPlayer = true }))
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showSoundProfiles) { NavigationStack { SoundProfilesView() } }
        .sheet(item: $editingSoundProfile) { profile in NavigationStack { SoundProfileEditor(profile: profile) } }
        .sheet(isPresented: $showFonts) {
            NavigationStack {
                FontSettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("ios-done") { showFonts = false } }
                }
            }
        }
        .sheet(isPresented: $showPlayer) {
            if reduceMotion { NowPlayingView(initialMode: playerMode) }
            else {
                NowPlayingView(initialMode: playerMode)
                    .navigationTransition(.zoom(sourceID: "sonora-now-playing", in: playerTransition))
            }
        }
        .modifier(LocalLibraryReviewSheet(presentation: localReviewBinding))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure: library.error = String(localized: "ios-import-error")
            }
        }
        .alert("ios-error-title", isPresented: Binding(
            get: { !showPlayer && (library.error != nil || playback.error != nil) },
            set: { if !$0 { library.error = nil; playback.error = nil } }
        )) {
            Button("ios-done", role: .cancel) { library.error = nil; playback.error = nil }
        } message: { Text(library.error ?? playback.error ?? "") }
        .onChange(of: library.isLoaded) { _, loaded in
            if loaded { playback.synchronizeLibrary(with: library.tracks) }
        }
        .onChange(of: library.tracks) { previous, tracks in
            if library.isLoaded {
                playback.synchronizeLibrary(with: tracks)
                let removed = Set(previous.map(\.id)).subtracting(tracks.map(\.id))
                localLibrary.forget(Array(removed))
            }
        }
        .onChange(of: account.revision) { _, _ in
            youtube.clear()
            playback.clearRemoteQueue()
            downloads.clearRemoteDownloads()
            settings.clearAccountData()
            catalog.loadHome(force: true)
            catalog.loadLibrary(isSignedIn: account.name != nil)
        }
        .onOpenURL(perform: open)
        .task {
            await library.load()
            await localLibrary.load()
            await account.restore()
            catalog.loadHome(force: true)
            catalog.loadLibrary(isSignedIn: account.name != nil)
            guard !didHandleLaunchURL else { return }
            didHandleLaunchURL = true
            #if DEBUG
            // The simulator runner can route without SpringBoard's external-URL confirmation.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--sonora-review-url"),
               arguments.indices.contains(index + 1), let url = URL(string: arguments[index + 1]) {
                open(url)
            }
            #endif
        }
    }

    private var localReviewBinding: Binding<LocalPlaylistReviewPresentation?> {
        #if DEBUG
        $localPlaylistPresentation
        #else
        .constant(nil)
        #endif
    }

    /// Shares URL validation between system deep links and the debug simulator runner.
    private func open(_ url: URL) {
        guard url.scheme == "sonora",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        #if DEBUG
        if url.host == "sessionreview" {
            account.reviewSessionStorage()
            return
        }
        if url.host == "downloadsreview" {
            selectedTab = .downloads
            library.reviewDownloads(downloads)
            return
        }
        if url.host == "guestprobe" {
            guestProbe.start(playback: playback) { playerMode = "artwork"; showPlayer = true }
            return
        }
        if url.host == "soundobservationreview" {
            settings.reviewAudioObservation(playback: playback)
            return
        }
        if url.host == "requestreview" {
            settings.reviewNativeRequests()
            return
        }
        if url.host == "scrobblereview" {
            settings.reviewScrobbling()
            return
        }
        if url.host == "lyricsstorereview" {
            localLyricsProbe.review(settings: settings)
            return
        }
        if url.host == "localplaylistrestore" {
            localLibraryProbe.restore(library: library) { localPlaylistPresentation = $0 }
            return
        }
        if url.host == "localplaylistreview" {
            localLibraryProbe.start(library: library) { localPlaylistPresentation = $0 }
            return
        }
        if url.host == "localreview" {
            library.reviewLocalPlayback(playback)
            return
        }
        if url.host == "soundprofilesreview" {
            settings.soundProfiles.review {
                settings.equalizerPreset = .custom
                playback.applyAudioGain()
                showSoundProfiles = true
            }
            return
        }
        if url.host == "soundprofileeditor", let profile = settings.soundProfiles.selected {
            editingSoundProfile = profile
            return
        }
        #endif
        let parameters = components.queryItems ?? []
        func value(_ name: String) -> String? { parameters.first { $0.name == name }?.value }
        #if DEBUG
        if url.host == "locallyrics" {
            localLyricsProbe.load(nil, title: value("title"), artist: value("artist"))
            return
        }
        if url.host == "fonts" {
            if let face = value("font"), ["system", "rounded", "Inter-Regular"].contains(face) {
                settings.typefaceID = face
            }
            showFonts = true
            return
        }
        #endif
        if url.host == "search", let query = value("q"), !query.isEmpty, query.utf8.count <= 512 {
            youtube.query = query
            selectedTab = .search
            youtube.submit(query)
        } else if url.host == "home" {
            selectedTab = .home
        } else if let id = value("id"), id.utf8.count == 11,
                  id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) {
            let track = youtube.tracks.first { $0.youtubeID == id } ?? MusicTrack(
                id: "youtube:" + id,
                title: String((value("title") ?? id).prefix(200)),
                artist: String((value("artist") ?? "").prefix(200)),
                filename: "", addedAt: .now, youtubeID: id,
                artworkURL: value("artwork").flatMap(URL.init(string:)).flatMap { url in
                    let host = url.host ?? ""
                    return url.scheme == "https" && (host.hasSuffix(".googleusercontent.com") || host.hasSuffix(".ytimg.com") || host.hasSuffix(".ggpht.com")) ? url : nil
                }
            )
            #if DEBUG
            if url.host == "queuereview" {
                playback.reviewQueue(track)
                playerMode = "queue"
                showPlayer = true
                return
            }
            if url.host == "review" {
                playerMode = value("mode") ?? "artwork"
                playback.prepareReview(track)
                showPlayer = true
                return
            }
            #endif
            if url.host == "play" {
                playerMode = "artwork"
                playback.play(track, in: [track])
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--sonora-review-live-controls") { playback.reviewLiveControls() }
                #endif
                showPlayer = true
            } else if url.host == "download" {
                downloads.enqueue(track)
                selectedTab = .downloads
            }
        }
    }

    private enum Destination: Hashable { case home, library, downloads, search }
}

/// iOS 26.1 can hide the accessory without rebuilding the tab hierarchy. The 26.0 fallback
/// omits the modifier altogether, since an empty accessory still reserves a glass capsule.
private struct PlayerAccessory: ViewModifier {
    @Environment(PlaybackController.self) private var playback
    let namespace: Namespace.ID
    let open: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: playback.current != nil) {
                MiniPlayer(open: open).matchedTransitionSource(id: "sonora-now-playing", in: namespace)
            }
        } else if playback.current != nil {
            content.tabViewBottomAccessory {
                MiniPlayer(open: open).matchedTransitionSource(id: "sonora-now-playing", in: namespace)
            }
        } else {
            content
        }
    }
}

/// Centers short native empty states, while letting large accessibility text scroll above
/// the safe area instead of pushing actions underneath the tab bar.
struct ScrollableEmptyState: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
}

/// Apple Music-style Home tab surfacing Pinned items, Recently Played, YouTube Music shelves, and Genres & Moods.
struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.spacing * 1.5) {
                if !settings.pins.isEmpty {
                    pinnedSection
                }

                if !settings.history.isEmpty {
                    historyShelfSection
                }

                if catalog.isLoadingHome && catalog.homeSections.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("ios-loading-home")
                            .padding(.vertical, Layout.spacing * 2)
                        Spacer()
                    }
                } else if let error = catalog.homeError, catalog.homeSections.isEmpty {
                    ContentUnavailableView {
                        Label("ios-home-unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("ios-retry") { catalog.loadHome(force: true) }.buttonStyle(.glass)
                    }
                    .padding(.vertical, Layout.spacing * 2)
                } else {
                    ForEach(catalog.homeSections) { section in
                        shelfView(section)
                    }
                }

                if !catalog.genres.isEmpty {
                    genresSection
                }
            }
            .padding(.vertical, Layout.spacing)
        }
        .appNavigationTitle("ios-home")
        .refreshable { catalog.loadHome(force: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios-settings", systemImage: "gearshape", action: openSettings)
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text("ios-pinned")
                .appFont(.title3, weight: .bold)
                .padding(.horizontal, Layout.spacing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Layout.spacing) {
                    ForEach(settings.pins) { pin in
                        pinnedCard(pin)
                    }
                }
                .padding(.horizontal, Layout.spacing)
            }
        }
    }

    @ViewBuilder
    private func pinnedCard(_ pin: PinnedItem) -> some View {
        switch pin.kind {
        case .track:
            if let track = pin.track {
                Button {
                    playback.play(track, in: [track])
                } label: {
                    SquareCard(title: pin.title, subtitle: pin.subtitle, artworkURL: pin.artworkURL)
                }
                .buttonStyle(.plain)
            }
        case .album:
            NavigationLink {
                AlbumDetailView(browseID: pin.targetID, fallbackTitle: pin.title, fallbackArtist: pin.subtitle, fallbackArtwork: pin.artworkURL)
            } label: {
                SquareCard(title: pin.title, subtitle: pin.subtitle, artworkURL: pin.artworkURL)
            }
            .buttonStyle(.plain)
        case .playlist:
            NavigationLink {
                PlaylistDetailView(playlistID: pin.targetID, fallbackTitle: pin.title, fallbackAuthor: pin.subtitle, fallbackArtwork: pin.artworkURL)
            } label: {
                SquareCard(title: pin.title, subtitle: pin.subtitle, artworkURL: pin.artworkURL)
            }
            .buttonStyle(.plain)
        case .artist:
            NavigationLink {
                ArtistDetailView(browseID: pin.targetID, fallbackName: pin.title, fallbackArtwork: pin.artworkURL)
            } label: {
                SquareCard(title: pin.title, subtitle: pin.subtitle, artworkURL: pin.artworkURL, circular: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var historyShelfSection: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text("ios-recently-played")
                .appFont(.title3, weight: .bold)
                .padding(.horizontal, Layout.spacing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Layout.spacing) {
                    ForEach(settings.history.prefix(12)) { track in
                        Button {
                            playback.play(track, in: settings.history)
                        } label: {
                            SquareCard(title: track.title, subtitle: track.artist, artworkURL: track.artworkURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.spacing)
            }
        }
    }

    private func shelfView(_ section: HomeShelfSection) -> some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text(section.title)
                .appFont(.title3, weight: .bold)
                .padding(.horizontal, Layout.spacing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Layout.spacing) {
                    ForEach(section.items) { item in
                        shelfItemView(item, in: section)
                    }
                }
                .padding(.horizontal, Layout.spacing)
            }
        }
    }

    @ViewBuilder
    private func shelfItemView(_ item: HomeShelfItem, in section: HomeShelfSection) -> some View {
        if let track = item.track {
            let sectionTracks = section.items.compactMap(\.track)
            Button {
                playback.play(track, in: sectionTracks.isEmpty ? [track] : sectionTracks)
            } label: {
                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
            }
            .buttonStyle(.plain)
        } else if let album = item.album {
            NavigationLink {
                AlbumDetailView(browseID: album.id, fallbackTitle: album.title, fallbackArtist: album.artist, fallbackArtwork: album.artworkURL)
            } label: {
                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
            }
            .buttonStyle(.plain)
        } else if let playlist = item.playlist {
            NavigationLink {
                PlaylistDetailView(playlistID: playlist.id, fallbackTitle: playlist.title, fallbackAuthor: playlist.author, fallbackArtwork: playlist.artworkURL)
            } label: {
                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
            }
            .buttonStyle(.plain)
        } else if let artist = item.artist {
            NavigationLink {
                ArtistDetailView(browseID: artist.id, fallbackName: artist.name, fallbackArtwork: artist.artworkURL)
            } label: {
                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL, circular: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text("ios-genres-moods")
                .appFont(.title3, weight: .bold)
                .padding(.horizontal, Layout.spacing)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Layout.compact), GridItem(.flexible(), spacing: Layout.compact)],
                spacing: Layout.compact
            ) {
                ForEach(catalog.genres) { genre in
                    NavigationLink {
                        GenreDetailView(genre: genre)
                    } label: {
                        GenreTile(genre: genre)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.spacing)
        }
    }
}

/// Reusable square or circular artwork card for Apple Music shelves and grids.
struct SquareCard: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    var side: CGFloat = Layout.cardArtwork
    var circular = false
    var fillsColumn = false

    var body: some View {
        VStack(alignment: circular ? .center : .leading, spacing: 6) {
            ArtworkImage(url: ArtworkRendition.url(artworkURL, side: fillsColumn ? Layout.collectionArtwork : side)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: circular ? "music.mic" : "music.note")
                    .appFont(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
            .frame(width: fillsColumn ? nil : side, height: fillsColumn ? nil : side)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(
                circular
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: Layout.cardRadius))
            )

            Text(title)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: fillsColumn ? nil : side, alignment: circular ? .center : .leading)
    }
}

/// Colorful Apple Music-style category tile for Genres & Moods.
private struct GenreTile: View {
    let genre: GenreCategory

    private var tileColor: Color {
        let rgb = genre.color
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        if r == 0 && g == 0 && b == 0 {
            return .accentColor
        }
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Layout.cardRadius)
                .fill(
                    LinearGradient(
                        colors: [tileColor.opacity(0.92), tileColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(genre.title)
                .appFont(.subheadline, weight: .bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(Layout.compact + 4)
        }
        .frame(height: 76)
    }
}

/// Apple Music-style Library view with category rows (Playlists, Artists, Albums, Songs, History, Pinned) and imported tracks.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(CatalogStore.self) private var catalog
    @Environment(SettingsStore.self) private var settings
    @Environment(AccountStore.self) private var account
    let importAction: () -> Void
    let openSettings: () -> Void

    @State private var showCreatePlaylist = false
    @State private var newPlaylistTitle = ""
    @State private var newPlaylistDescription = ""
    @State private var selectedRecentAlbum: String?

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
            } else {
                List {
                    Section {
                        NavigationLink {
                            PlaylistsCollectionView()
                        } label: {
                            Label("ios-playlists", systemImage: "music.note.list")
                        }
                        NavigationLink {
                            ArtistsCollectionView()
                        } label: {
                            Label("ios-artists", systemImage: "music.mic")
                        }
                        NavigationLink {
                            AlbumsCollectionView()
                        } label: {
                            Label("ios-albums", systemImage: "square.stack")
                        }
                        NavigationLink {
                            SongsCollectionView(importAction: importAction)
                        } label: {
                            Label("ios-songs", systemImage: "music.note")
                        }
                        NavigationLink { DownloadsView() } label: {
                            Label("ios-downloaded", systemImage: "arrow.down.circle")
                        }
                        NavigationLink {
                            HistoryCollectionView()
                        } label: {
                            Label("ios-history", systemImage: "clock.arrow.circlepath")
                        }
                        if !settings.pins.isEmpty {
                            NavigationLink {
                                PinsCollectionView()
                            } label: {
                                Label("ios-pinned", systemImage: "pin")
                            }
                        }
                    }.labelStyle(LibraryCategoryLabelStyle())

                    Section {
                        NavigationLink { LocalFavoritesView() } label: { Label("ios-local-favorites", systemImage: "star.fill") }
                    }
                    if !library.tracks.isEmpty {
                        Section("ios-recently-added") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.cardArtwork), spacing: Layout.spacing)],
                                      alignment: .leading, spacing: Layout.spacing) {
                                ForEach(LocalAlbum.collect(library.tracks).sorted {
                                    ($0.tracks.map(\.addedAt).max() ?? .distantPast) > ($1.tracks.map(\.addedAt).max() ?? .distantPast)
                                }.prefix(8)) { album in
                                    Button { selectedRecentAlbum = album.id } label: {
                                        SquareCard(title: album.title, subtitle: album.artist,
                                            artworkURL: album.tracks.first { $0.displayArtworkURL != nil }?.displayArtworkURL)
                                    }.buttonStyle(.plain)
                                }
                                ForEach(library.tracks.filter { ($0.albumTitle ?? "").isEmpty }.prefix(8)) { track in
                                    Button { playback.play(track, in: library.tracks) } label: {
                                        SquareCard(title: track.title, subtitle: track.artist, artworkURL: track.displayArtworkURL)
                                    }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button("ios-delete", role: .destructive) { Task { await library.remove(track) } }
                                    }
                                }
                            }
                            .padding(.vertical, Layout.compact)
                            .listRowSeparator(.hidden)
                        }
                    } else if !catalog.likedSongs.isEmpty {
                        Section("ios-liked-songs") {
                            ForEach(catalog.likedSongs.prefix(20)) { track in
                                TrackRow(track: track) { playback.play(track, in: catalog.likedSongs) }
                            }
                        }
                    } else {
                        Section {
                            VStack(spacing: Layout.compact) {
                                Image(systemName: "music.note")
                                    .appFont(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("ios-your-music")
                                    .appFont(.headline)
                                Text("ios-import-description")
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("ios-import", systemImage: "plus", action: importAction)
                                    .buttonStyle(.glassProminent)
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Layout.spacing * 1.5)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    catalog.loadLibrary(isSignedIn: account.name != nil)
                }
            }
        }
        .appNavigationTitle("ios-library")
        .navigationDestination(item: $selectedRecentAlbum) { LocalAlbumView(albumID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios-import", systemImage: "plus", action: importAction)
                    .disabled(library.isImporting || !library.isLoaded)
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios-settings", systemImage: "gearshape", action: openSettings)
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

/// Library > Playlists sub-screen with playlist creation and navigation.
struct PlaylistsCollectionView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibraryStore.self) private var local
    @Environment(LibraryStore.self) private var library
    @State private var createLocal = false
    @State private var createYouTube = false
    @State private var createdID: String?
    @AppStorage("sonora.playlists.grid") private var grid = true

    var body: some View {
        Group {
            if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Layout.spacing), GridItem(.flexible(), spacing: Layout.spacing)],
                        alignment: .leading, spacing: Layout.spacing) {
                        ForEach(local.playlists) { playlist in
                            NavigationLink { LocalPlaylistView(playlistID: playlist.id) } label: {
                                SquareCard(title: playlist.title, subtitle: String(localized: "ios-on-my-iphone"),
                                    artworkURL: playlist.tracks(in: library.tracks).first { $0.displayArtworkURL != nil }?.displayArtworkURL,
                                    fillsColumn: true)
                            }.buttonStyle(.plain)
                        }
                        ForEach(catalog.savedPlaylists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistID: playlist.id, fallbackTitle: playlist.title,
                                    fallbackAuthor: playlist.author, fallbackArtwork: playlist.artworkURL)
                            } label: {
                                SquareCard(title: playlist.title, subtitle: playlist.author,
                                    artworkURL: playlist.artworkURL, fillsColumn: true)
                            }.buttonStyle(.plain)
                        }
                    }.padding(Layout.spacing)
                    if local.playlists.isEmpty && catalog.savedPlaylists.isEmpty {
                        ContentUnavailableView("ios-playlists", systemImage: "music.note.list",
                            description: Text("ios-local-playlists-description"))
                    }
                    if catalog.isLoadingLibrary { ProgressView("ios-loading-library") }
                    if let error = local.error { Text(error).foregroundStyle(.secondary) }
                    if let error = catalog.libraryError { Text(error).foregroundStyle(.secondary) }
                }
            } else {
                playlistList
            }
        }
        .appNavigationTitle("ios-playlists")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("ios-on-my-iphone", systemImage: "iphone") { createLocal = true }
                        .disabled(local.isBusy || !local.isLoaded)
                    if account.name != nil { Button("ios-youtube-music", systemImage: "play.rectangle") { createYouTube = true } }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("ios-create-playlist"))
                Menu {
                    Picker("ios-view-as", selection: $grid) {
                        Label("ios-grid", systemImage: "square.grid.2x2").tag(true)
                        Label("ios-list", systemImage: "list.bullet").tag(false)
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .accessibilityLabel(Text("ios-view-as"))
            }
        }
        .navigationDestination(item: $createdID) { LocalPlaylistView(playlistID: $0) }
        .sheet(isPresented: $createLocal) {
            NavigationStack { CreateLocalPlaylistView(trackIDs: []) { createdID = $0 } }
        }
        .sheet(isPresented: $createYouTube) { NavigationStack { YouTubePlaylistCreationView() } }
    }

    private var playlistList: some View {
        List {
            Section {
                Button("ios-create-playlist", systemImage: "plus") { createLocal = true }
                    .disabled(local.isBusy || !local.isLoaded)
                ForEach(local.playlists) { playlist in
                    NavigationLink { LocalPlaylistView(playlistID: playlist.id) } label: {
                        LocalPlaylistLabel(playlist: playlist, tracks: playlist.tracks(in: library.tracks))
                    }
                }
            } header: { Text("ios-on-my-iphone") } footer: { Text("ios-local-playlists-description") }
            if account.name != nil {
                Section("ios-youtube-music") {
                    Button("ios-create-playlist", systemImage: "plus") { createYouTube = true }
                    if catalog.isLoadingLibrary { ProgressView("ios-loading-library") }
                    ForEach(catalog.savedPlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id, fallbackTitle: playlist.title,
                                fallbackAuthor: playlist.author, fallbackArtwork: playlist.artworkURL)
                        } label: {
                            HStack(spacing: Layout.spacing) {
                                ArtworkView(url: playlist.artworkURL, side: Layout.rowArtwork)
                                VStack(alignment: .leading, spacing: Layout.compact / 2) {
                                    Text(playlist.title).appFont(.body, weight: .medium).lineLimit(2)
                                    Text(playlist.author).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if let error = local.error {
                Section { Text(error).foregroundStyle(.secondary); Button("ios-retry") { local.refresh() } }
            }
            if let error = catalog.libraryError { Text(error).foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
    }
}

/// Library > Artists sub-screen combining subscribed YouTube artists and imported local artists.
struct ArtistsCollectionView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var local

    private struct ArtistEntry: Identifiable {
        let id: String
        let name: String
        let artwork: URL?
        let remote: CatalogArtist?
    }

    private var artists: [ArtistEntry] {
        let names = Array(Dictionary(library.tracks.map { ($0.artist.lowercased(), $0.artist) },
            uniquingKeysWith: { first, _ in first }).values)
        return names.map { name in
            ArtistEntry(id: "local:" + name.lowercased(), name: name,
                artwork: library.tracks.first { $0.artist == name }?.displayArtworkURL, remote: nil)
        } + catalog.savedArtists.map {
            ArtistEntry(id: "remote:" + $0.id, name: $0.name, artwork: $0.artworkURL, remote: $0)
        }
    }

    var body: some View {
        Group {
            if artists.isEmpty {
                ContentUnavailableView("ios-artists", systemImage: "music.mic",
                    description: Text("ios-artists-empty-description"))
                    .modifier(ScrollableEmptyState())
            } else {
                List {
                    ForEach(LibraryAlphabet.groups(artists, title: { $0.name })) { group in
                        Section {
                            ForEach(group.items) { artist in
                                NavigationLink {
                                    if let remote = artist.remote {
                                        ArtistDetailView(browseID: remote.id, fallbackName: remote.name, fallbackArtwork: remote.artworkURL)
                                    } else { LocalArtistView(name: artist.name) }
                                } label: {
                                    HStack(spacing: Layout.spacing) {
                                        ArtworkView(url: artist.artwork, side: Layout.rowArtwork)
                                            .placeholderSymbol("music.mic").clipShape(Circle())
                                        Text(artist.name).appFont(.body)
                                    }
                                }
                                .contextMenu {
                                    if artist.remote == nil {
                                        Button(local.isFavorite(artist.name.lowercased(), category: .artists) ? "ios-remove-favorite" : "ios-favorite",
                                               systemImage: local.isFavorite(artist.name.lowercased(), category: .artists) ? "star.slash" : "star") {
                                            local.toggleFavorite(artist.name.lowercased(), category: .artists)
                                        }.disabled(local.isBusy || !local.isLoaded)
                                    }
                                }
                            }
                        } header: { Text(group.id).appFont(.headline) }
                        .sectionIndexLabel(Text(group.id))
                    }
                }
                .listStyle(.plain)
                .listSectionIndexVisibility(.visible)
            }
        }
        .appNavigationTitle("ios-artists")
    }
}

/// Library > Albums sub-screen.
struct AlbumsCollectionView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(AccountStore.self) private var account
    @Environment(PlaybackController.self) private var playback
    @AppStorage("sonora.albums.grid") private var grid = true
    @State private var sort = AlbumSort.artist
    @State private var playTask: Task<Void, Never>?
    @State private var loadingPlayback = false
    @State private var error: String?

    private enum AlbumSort: String, CaseIterable, Identifiable {
        case title, artist, year
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .title: "ios-title"; case .artist: "ios-artist"; case .year: "ios-year" }
        }
    }

    private struct AlbumEntry: Identifiable {
        let id: String
        let title: String
        let artist: String
        let artwork: URL?
        let year: UInt16?
        let local: LocalAlbum?
        let remote: CatalogAlbum?
    }

    private var albums: [AlbumEntry] {
        LocalAlbum.collect(library.tracks).map {
            AlbumEntry(id: "local:" + $0.id, title: $0.title, artist: $0.artist,
                artwork: $0.tracks.first { $0.displayArtworkURL != nil }?.displayArtworkURL,
                year: nil, local: $0, remote: nil)
        } + catalog.savedAlbums.map {
            AlbumEntry(id: "remote:" + $0.id, title: $0.title, artist: $0.artist,
                artwork: $0.artworkURL, year: $0.year, local: nil, remote: $0)
        }
    }

    private var groups: [AlphabeticGroup<AlbumEntry>] {
        LibraryAlphabet.groups(albums) { album in
            switch sort {
            case .title: album.title
            case .artist: album.artist
            case .year: album.year.map(String.init) ?? "#"
            }
        }
    }

    var body: some View {
        Group {
            if albums.isEmpty {
                ContentUnavailableView("ios-albums", systemImage: "square.stack",
                    description: Text(account.name == nil ? LocalizedStringKey("ios-sign-in-library-description") : LocalizedStringKey("ios-albums-empty-description")))
                    .modifier(ScrollableEmptyState())
            } else {
                List {
                    CollectionPlayShuffleHeader(playAction: { playAlbums(shuffled: false) },
                        shuffleAction: { playAlbums(shuffled: true) })
                        .disabled(loadingPlayback).listRowSeparator(.hidden)
                    if loadingPlayback { ProgressView("ios-loading-library") }
                    if let error { Text(error).foregroundStyle(.secondary) }
                    ForEach(groups) { group in
                        Section {
                            if grid {
                                ForEach(Array(stride(from: 0, to: group.items.count, by: 2)), id: \.self) { start in
                                    HStack(alignment: .top, spacing: Layout.spacing) {
                                        albumLink(group.items[start], grid: true)
                                        if start + 1 < group.items.count { albumLink(group.items[start + 1], grid: true) }
                                        else { Color.clear.frame(maxWidth: .infinity) }
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: Layout.compact, leading: Layout.spacing,
                                        bottom: Layout.compact, trailing: Layout.spacing))
                                }
                            } else {
                                ForEach(group.items) { album in albumLink(album, grid: false) }
                            }
                        } header: { Text(group.id).appFont(.headline) }
                        .sectionIndexLabel(Text(group.id))
                    }
                }
                .listStyle(.plain)
                .listSectionIndexVisibility(.visible)
            }
        }
        .appNavigationTitle("ios-albums")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("ios-view-as", selection: $grid) {
                    Label("ios-grid", systemImage: "square.grid.2x2").tag(true)
                    Label("ios-list", systemImage: "list.bullet").tag(false)
                }
                Picker("ios-sort-by", selection: $sort) {
                    ForEach(AlbumSort.allCases) { Label($0.label, systemImage: "arrow.up").tag($0) }
                }
            } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel(Text("ios-sort-by"))
        } }
        .onDisappear { playTask?.cancel(); playTask = nil; loadingPlayback = false }
    }

    private func albumLink(_ album: AlbumEntry, grid: Bool) -> some View {
        NavigationLink {
            if let local = album.local { LocalAlbumView(albumID: local.id) }
            else if let remote = album.remote {
                AlbumDetailView(browseID: remote.id, fallbackTitle: remote.title,
                    fallbackArtist: remote.artist, fallbackArtwork: remote.artworkURL)
            }
        } label: {
            if grid {
                SquareCard(title: album.title, subtitle: album.artist, artworkURL: album.artwork, fillsColumn: true)
            } else {
                DownloadedCollectionLabel(title: album.title, subtitle: album.artist, artwork: album.artwork)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fetches actual album sequences before starting; cancellation never starts partial playback.
    private func playAlbums(shuffled: Bool) {
        playTask?.cancel()
        let selection = groups.flatMap(\.items)
        loadingPlayback = true
        error = nil
        playTask = Task { @MainActor in
            defer { loadingPlayback = false }
            do {
                var tracks: [MusicTrack] = []
                for album in selection {
                    try Task.checkCancellation()
                    if let local = album.local { tracks += local.tracks }
                    else if let remote = album.remote {
                        tracks += try await NativeProvider.album(browseID: remote.id).tracks.map(\.track)
                    }
                }
                try Task.checkCancellation()
                if shuffled { playback.playShuffled(tracks, source: String(localized: "ios-albums")) }
                else if let first = tracks.first { playback.play(first, in: tracks, source: String(localized: "ios-albums")) }
            } catch is CancellationError {} catch {
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
            }
        }
    }
}

/// Library > Songs sub-screen combining Imported Local Songs and Liked YouTube Songs.
struct SongsCollectionView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaybackController.self) private var playback
    let importAction: () -> Void

    private var allSongs: [MusicTrack] {
        var seen: Set<String> = []
        return (library.tracks + catalog.likedSongs).filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if allSongs.isEmpty {
                ContentUnavailableView {
                    Label("ios-songs", systemImage: "music.note")
                } description: {
                    Text("ios-import-description")
                } actions: {
                    Button("ios-import", systemImage: "plus", action: importAction)
                        .buttonStyle(.glassProminent)
                }
                .modifier(ScrollableEmptyState())
            } else {
                List {
                    Section {
                        CollectionPlayShuffleHeader(
                            playAction: {
                                if let first = allSongs.first { playback.play(first, in: allSongs) }
                            },
                            shuffleAction: { playback.playShuffled(allSongs) }
                        )
                    }
                    ForEach(LibraryAlphabet.groups(allSongs, title: { $0.title })) { group in
                        Section {
                            ForEach(group.items) { track in
                                TrackRow(track: track) { playback.play(track, in: allSongs) }
                            }
                        } header: { Text(group.id).appFont(.headline) }
                        .sectionIndexLabel(Text(group.id))
                    }
                }
                .listStyle(.plain)
                .listSectionIndexVisibility(.visible)
            }
        }
        .appNavigationTitle("ios-songs")
    }
}

/// Library > History sub-screen.
struct HistoryCollectionView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        Group {
            if settings.history.isEmpty {
                ContentUnavailableView(
                    "ios-history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("ios-history-empty-description")
                )
                .modifier(ScrollableEmptyState())
            } else {
                List {
                    ForEach(settings.history) { track in
                        TrackRow(track: track) { playback.play(track, in: settings.history) }
                            .swipeActions {
                                Button("ios-delete", role: .destructive) {
                                    settings.removeFromHistory(track)
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .appNavigationTitle("ios-history")
        .toolbar {
            if !settings.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ios-clear", role: .destructive) { settings.clearHistory() }
                }
            }
        }
    }
}

/// Library > Pinned sub-screen.
struct PinsCollectionView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        List {
            ForEach(settings.pins) { pin in
                Group {
                    switch pin.kind {
                    case .track:
                        if let track = pin.track {
                            TrackRow(track: track) { playback.play(track, in: [track]) }
                        }
                    case .album:
                        NavigationLink {
                            AlbumDetailView(browseID: pin.targetID, fallbackTitle: pin.title, fallbackArtist: pin.subtitle, fallbackArtwork: pin.artworkURL)
                        } label: {
                            Label(pin.title, systemImage: "square.stack")
                        }
                    case .playlist:
                        NavigationLink {
                            PlaylistDetailView(playlistID: pin.targetID, fallbackTitle: pin.title, fallbackAuthor: pin.subtitle, fallbackArtwork: pin.artworkURL)
                        } label: {
                            Label(pin.title, systemImage: "music.note.list")
                        }
                    case .artist:
                        NavigationLink {
                            ArtistDetailView(browseID: pin.targetID, fallbackName: pin.title, fallbackArtwork: pin.artworkURL)
                        } label: {
                            Label(pin.title, systemImage: "music.mic")
                        }
                    }
                }
                .swipeActions {
                    Button("ios-unpin", role: .destructive) {
                        settings.togglePin(pin)
                    }
                }
            }
        }
        .listStyle(.plain)
        .appNavigationTitle("ios-pinned")
    }
}

/// Apple Music dual Play & Shuffle pill buttons for Album, Playlist, Artist, and Collection headers.
struct CollectionPlayShuffleHeader: View {
    let playAction: () -> Void
    let shuffleAction: () -> Void

    var body: some View {
        HStack(spacing: Layout.spacing) {
            transport("ios-play", symbol: "play.fill", action: playAction)
            transport("ios-shuffle", symbol: "shuffle", action: shuffleAction)
        }
        .padding(.vertical, Layout.compact / 2)
    }

    private func transport(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: Layout.control)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PlayerControlStyle())
    }
}

/// Apple Music-style Album detail screen with hero artwork, Play/Shuffle pills, and track list.
struct AlbumDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings

    let browseID: String
    let fallbackTitle: String
    let fallbackArtist: String
    let fallbackArtwork: URL?

    @State private var detail: NativeProvider.AlbumDetailPayload?
    @State private var isLoading = true
    @State private var error: String?

    private var tracks: [MusicTrack] {
        detail?.tracks.map(\.track) ?? []
    }

    var body: some View {
        List {
            Section {
                MusicCollectionHeader(title: detail?.title ?? fallbackTitle,
                    subtitle: detail?.artist ?? fallbackArtist,
                    artworkURL: detail?.artwork_url ?? fallbackArtwork, tracks: tracks,
                    description: detail?.year.map { String($0) }, symbol: "square.stack")
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ForEach(tracks) { track in
                    TrackRow(track: track) { playback.play(track, in: tracks, source: detail?.title ?? fallbackTitle) }
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios-download", systemImage: "arrow.down.circle") {
                        downloads.enqueueAll(tracks)
                    }
                    .disabled(tracks.isEmpty)
                    Button("ios-add-to-queue", systemImage: "text.badge.plus") {
                        playback.addToQueue(tracks)
                    }
                    .disabled(tracks.isEmpty)
                    let pinID = "album:" + browseID
                    Button(
                        settings.isPinned(pinID) ? "ios-unpin" : "ios-pin",
                        systemImage: settings.isPinned(pinID) ? "pin.slash" : "pin"
                    ) {
                        settings.togglePin(PinnedItem(
                            id: pinID,
                            kind: .album,
                            title: detail?.title ?? fallbackTitle,
                            subtitle: detail?.artist ?? fallbackArtist,
                            artworkURL: detail?.artwork_url ?? fallbackArtwork,
                            targetID: browseID,
                            track: nil
                        ))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            do {
                detail = try await NativeProvider.album(browseID: browseID)
                isLoading = false
            } catch {
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                isLoading = false
            }
        }
    }
}

/// Apple Music-style Playlist detail screen with hero artwork, Play/Shuffle pills, and playlist management.
struct PlaylistDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(CatalogStore.self) private var catalog
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    let playlistID: String
    let fallbackTitle: String
    let fallbackAuthor: String
    let fallbackArtwork: URL?

    @State private var detail: NativeProvider.PlaylistDetailPayload?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showRename = false
    @State private var renameTitle = ""

    private var tracks: [MusicTrack] {
        detail?.tracks.map(\.track) ?? []
    }

    var body: some View {
        List {
            Section {
                MusicCollectionHeader(title: detail?.title ?? fallbackTitle,
                    subtitle: detail?.author ?? fallbackAuthor,
                    artworkURL: detail?.artwork_url ?? fallbackArtwork, tracks: tracks,
                    description: detail?.description)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ForEach(tracks) { track in
                    TrackRow(track: track) { playback.play(track, in: tracks, source: detail?.title ?? fallbackTitle) }
                        .swipeActions {
                            if detail?.editable == true,
                               let videoID = track.youtubeID,
                               let setVideoID = track.setVideoID {
                                Button("ios-delete", role: .destructive) {
                                    Task {
                                        try? await NativeProvider.removePlaylistTrack(
                                            playlistID: playlistID,
                                            videoID: videoID,
                                            setVideoID: setVideoID
                                        )
                                        detail = try? await NativeProvider.playlist(playlistID: playlistID)
                                    }
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios-download", systemImage: "arrow.down.circle") {
                        downloads.enqueuePlaylist(id: playlistID, title: detail?.title ?? fallbackTitle,
                            author: detail?.author ?? fallbackAuthor, artwork: detail?.artwork_url ?? fallbackArtwork, tracks: tracks)
                    }
                    .disabled(tracks.isEmpty)
                    Button("ios-add-to-queue", systemImage: "text.badge.plus") {
                        playback.addToQueue(tracks)
                    }
                    .disabled(tracks.isEmpty)
                    let pinID = "playlist:" + playlistID
                    Button(
                        settings.isPinned(pinID) ? "ios-unpin" : "ios-pin",
                        systemImage: settings.isPinned(pinID) ? "pin.slash" : "pin"
                    ) {
                        settings.togglePin(PinnedItem(
                            id: pinID,
                            kind: .playlist,
                            title: detail?.title ?? fallbackTitle,
                            subtitle: detail?.author ?? fallbackAuthor,
                            artworkURL: detail?.artwork_url ?? fallbackArtwork,
                            targetID: playlistID,
                            track: nil
                        ))
                    }
                    if detail?.editable == true {
                        Button("ios-rename-playlist", systemImage: "pencil") {
                            renameTitle = detail?.title ?? fallbackTitle
                            showRename = true
                        }
                        Button("ios-delete-playlist", systemImage: "trash", role: .destructive) {
                            Task {
                                try? await NativeProvider.deletePlaylist(playlistID: playlistID)
                                catalog.loadLibrary(isSignedIn: account.name != nil)
                                dismiss()
                            }
                        }
                    } else if account.name != nil {
                        let isSaved = detail?.liked == true
                        Button(
                            isSaved ? "ios-remove-from-library" : "ios-save-to-library",
                            systemImage: isSaved ? "minus.circle" : "plus.circle"
                        ) {
                            Task {
                                try? await NativeProvider.ratePlaylist(playlistID: playlistID, liked: !isSaved)
                                detail = try? await NativeProvider.playlist(playlistID: playlistID)
                                catalog.loadLibrary(isSignedIn: account.name != nil)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("ios-rename-playlist", isPresented: $showRename) {
            TextField("ios-playlist-title", text: $renameTitle)
            Button("ios-done") {
                let updated = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !updated.isEmpty else { return }
                Task {
                    try? await NativeProvider.renamePlaylist(playlistID: playlistID, title: updated)
                    detail = try? await NativeProvider.playlist(playlistID: playlistID)
                }
            }
        }
        .task {
            do {
                detail = try await NativeProvider.playlist(playlistID: playlistID)
                isLoading = false
            } catch {
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                isLoading = false
            }
        }
    }
}

/// Apple Music-style Artist detail screen with circular portrait, Top Songs, Albums, Singles, and Related Artists.
struct ArtistDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(SettingsStore.self) private var settings

    let browseID: String
    let fallbackName: String
    let fallbackArtwork: URL?

    @State private var detail: NativeProvider.ArtistDetailPayload?
    @State private var isLoading = true
    @State private var error: String?

    private var topSongs: [MusicTrack] {
        detail?.top_songs.map(\.track) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.spacing * 1.5) {
                VStack(spacing: Layout.compact) {
                    AsyncImage(url: ArtworkRendition.url(detail?.artwork_url ?? fallbackArtwork, side: Layout.detailArtwork)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.mic")
                            .appFont(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 8)

                    Text(detail?.name ?? fallbackName)
                        .appFont(.title, weight: .bold)
                        .multilineTextAlignment(.center)
                    if let subs = detail?.subscribers, !subs.isEmpty {
                        Text(subs)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    CollectionPlayShuffleHeader(
                        playAction: {
                            if let first = topSongs.first { playback.play(first, in: topSongs) }
                        },
                        shuffleAction: { playback.playShuffled(topSongs) }
                    )
                    .disabled(topSongs.isEmpty)
                    .padding(.horizontal, Layout.spacing)
                }
                .frame(maxWidth: .infinity)

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error {
                    Text(error).foregroundStyle(.secondary).padding(.horizontal, Layout.spacing)
                } else {
                    if !topSongs.isEmpty {
                        VStack(alignment: .leading, spacing: Layout.compact) {
                            Text("ios-top-songs")
                                .appFont(.title3, weight: .bold)
                                .padding(.horizontal, Layout.spacing)
                            ForEach(topSongs) { track in
                                TrackRow(track: track) { playback.play(track, in: topSongs) }
                                    .padding(.horizontal, Layout.spacing)
                            }
                        }
                    }

                    if let albums = detail?.albums.map(\.album), !albums.isEmpty {
                        albumShelf(title: "ios-albums", albums: albums)
                    }

                    if let singles = detail?.singles.map(\.album), !singles.isEmpty {
                        albumShelf(title: "ios-singles", albums: singles)
                    }

                    if let related = detail?.related.map(\.artist), !related.isEmpty {
                        VStack(alignment: .leading, spacing: Layout.compact) {
                            Text("ios-similar-artists")
                                .appFont(.title3, weight: .bold)
                                .padding(.horizontal, Layout.spacing)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Layout.spacing) {
                                    ForEach(related) { item in
                                        NavigationLink {
                                            ArtistDetailView(browseID: item.id, fallbackName: item.name, fallbackArtwork: item.artworkURL)
                                        } label: {
                                            SquareCard(title: item.name, subtitle: "", artworkURL: item.artworkURL, circular: true)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, Layout.spacing)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Layout.spacing)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let pinID = "artist:" + browseID
                Button {
                    settings.togglePin(PinnedItem(
                        id: pinID,
                        kind: .artist,
                        title: detail?.name ?? fallbackName,
                        subtitle: "",
                        artworkURL: detail?.artwork_url ?? fallbackArtwork,
                        targetID: browseID,
                        track: nil
                    ))
                } label: {
                    Image(systemName: settings.isPinned(pinID) ? "pin.fill" : "pin")
                }
            }
        }
        .task {
            do {
                detail = try await NativeProvider.artist(browseID: browseID)
                isLoading = false
            } catch {
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                isLoading = false
            }
        }
    }

    private func albumShelf(title: LocalizedStringKey, albums: [CatalogAlbum]) -> some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text(title)
                .appFont(.title3, weight: .bold)
                .padding(.horizontal, Layout.spacing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.spacing) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(
                                browseID: album.id,
                                fallbackTitle: album.title,
                                fallbackArtist: album.artist,
                                fallbackArtwork: album.artworkURL
                            )
                        } label: {
                            SquareCard(
                                title: album.title,
                                subtitle: album.year.map(String.init) ?? album.artist,
                                artworkURL: album.artworkURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.spacing)
            }
        }
    }
}

/// Genre / Mood detail screen displaying playlists and shelves for a selected category.
struct GenreDetailView: View {
    @Environment(PlaybackController.self) private var playback
    let genre: GenreCategory
    @State private var sections: [HomeShelfSection] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.spacing * 1.5) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, Layout.spacing * 2)
                } else if let error {
                    Text(error).foregroundStyle(.secondary).padding(.horizontal, Layout.spacing)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: Layout.compact) {
                            Text(section.title)
                                .appFont(.title3, weight: .bold)
                                .padding(.horizontal, Layout.spacing)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: Layout.spacing) {
                                    ForEach(section.items) { item in
                                        if let playlist = item.playlist {
                                            NavigationLink {
                                                PlaylistDetailView(
                                                    playlistID: playlist.id,
                                                    fallbackTitle: playlist.title,
                                                    fallbackAuthor: playlist.author,
                                                    fallbackArtwork: playlist.artworkURL
                                                )
                                            } label: {
                                                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
                                            }
                                            .buttonStyle(.plain)
                                        } else if let album = item.album {
                                            NavigationLink {
                                                AlbumDetailView(
                                                    browseID: album.id,
                                                    fallbackTitle: album.title,
                                                    fallbackArtist: album.artist,
                                                    fallbackArtwork: album.artworkURL
                                                )
                                            } label: {
                                                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
                                            }
                                            .buttonStyle(.plain)
                                        } else if let track = item.track {
                                            Button {
                                                playback.play(track, in: [track])
                                            } label: {
                                                SquareCard(title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, Layout.spacing)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Layout.spacing)
        }
        .appNavigationTitle(genre.title)
        .task {
            do {
                sections = try await NativeProvider.genre(params: genre.params)
                isLoading = false
            } catch {
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                isLoading = false
            }
        }
    }
}

/// Apple Music-style Search tab with YouTube Music & Library scopes, filter pills (All, Songs, Albums, Artists, Playlists), suggestions, and Genres grid.
struct SearchView: View {
    private enum Scope: Hashable { case youtube, library }
    private enum Filter: Hashable { case all, songs, albums, artists, playlists }

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSearch.self) private var youtube
    @Environment(CatalogStore.self) private var catalog

    @State private var scope = Scope.youtube
    @State private var filter = Filter.all

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

            if scope == .youtube && youtube.hasSearched {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Layout.compact) {
                        filterPill("ios-filter-all", value: .all)
                        filterPill("ios-songs", value: .songs)
                        filterPill("ios-albums", value: .albums)
                        filterPill("ios-artists", value: .artists)
                        filterPill("ios-playlists", value: .playlists)
                    }
                    .padding(.horizontal, Layout.spacing)
                    .padding(.bottom, Layout.compact)
                }
            }

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
                    }
                    .listStyle(.plain)
                }
            }
        }
        .appNavigationTitle("ios-search")
        .searchable(text: $youtube.query, prompt: "ios-search-prompt")
        .onSubmit(of: .search) { if scope == .youtube { youtube.submit(youtube.query) } }
        .onChange(of: youtube.query) { _, value in
            if value.isEmpty { youtube.clear() }
            else if scope == .youtube && !youtube.hasSearched { youtube.updateSuggestions(value) }
        }
    }

    private func filterPill(_ title: LocalizedStringKey, value: Filter) -> some View {
        Button {
            filter = value
        } label: {
            Text(title)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(filter == value ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    filter == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
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
            if !youtube.suggestions.isEmpty {
                List(youtube.suggestions, id: \.self) { suggestion in
                    Button {
                        youtube.query = suggestion
                        youtube.submit(suggestion)
                    } label: {
                        Label(suggestion, systemImage: "magnifyingglass")
                    }
                }
                .listStyle(.plain)
            } else if !catalog.genres.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        Text("ios-browse-categories")
                            .appFont(.title3, weight: .bold)
                            .padding(.horizontal, Layout.spacing)
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: Layout.compact), GridItem(.flexible(), spacing: Layout.compact)],
                            spacing: Layout.compact
                        ) {
                            ForEach(catalog.genres) { genre in
                                NavigationLink {
                                    GenreDetailView(genre: genre)
                                } label: {
                                    GenreTile(genre: genre)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Layout.spacing)
                    }
                    .padding(.vertical, Layout.compact)
                }
            } else {
                ContentUnavailableView("ios-search-youtube", systemImage: "magnifyingglass", description: Text("ios-search-youtube-description"))
                    .modifier(ScrollableEmptyState())
            }
        } else if youtube.tracks.isEmpty && youtube.albums.isEmpty && youtube.artists.isEmpty && youtube.playlists.isEmpty {
            ContentUnavailableView.search(text: youtube.query)
                .modifier(ScrollableEmptyState())
        } else {
            List {
                if (filter == .all || filter == .songs) && !youtube.tracks.isEmpty {
                    Section("ios-songs") {
                        ForEach(filter == .all ? Array(youtube.tracks.prefix(8)) : youtube.tracks) { track in
                            TrackRow(track: track) { playback.play(track, in: youtube.tracks) }
                                .disabled(track.available == false)
                        }
                    }
                }
                if (filter == .all || filter == .albums) && !youtube.albums.isEmpty {
                    Section("ios-albums") {
                        ForEach(youtube.albums) { album in
                            NavigationLink {
                                AlbumDetailView(
                                    browseID: album.id,
                                    fallbackTitle: album.title,
                                    fallbackArtist: album.artist,
                                    fallbackArtwork: album.artworkURL
                                )
                            } label: {
                                HStack(spacing: Layout.spacing) {
                                    AsyncImage(url: album.artworkURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "square.stack")
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(.quaternary)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.title).appFont(.body, weight: .medium).lineLimit(1)
                                        Text(album.artist).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                if (filter == .all || filter == .artists) && !youtube.artists.isEmpty {
                    Section("ios-artists") {
                        ForEach(youtube.artists) { artist in
                            NavigationLink {
                                ArtistDetailView(browseID: artist.id, fallbackName: artist.name, fallbackArtwork: artist.artworkURL)
                            } label: {
                                HStack(spacing: Layout.spacing) {
                                    AsyncImage(url: artist.artworkURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "music.mic")
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(.quaternary)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    Text(artist.name).appFont(.body, weight: .medium).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                if (filter == .all || filter == .playlists) && !youtube.playlists.isEmpty {
                    Section("ios-playlists") {
                        ForEach(youtube.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistID: playlist.id,
                                    fallbackTitle: playlist.title,
                                    fallbackAuthor: playlist.author,
                                    fallbackArtwork: playlist.artworkURL
                                )
                            } label: {
                                HStack(spacing: Layout.spacing) {
                                    AsyncImage(url: playlist.artworkURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "music.note.list")
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(.quaternary)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.title).appFont(.body, weight: .medium).lineLimit(1)
                                        Text(playlist.author).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

/// Comprehensive Settings sheet accommodating all Sonora desktop settings on iPhone.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmRemoveDownloads = false

    var body: some View {
        @Bindable var downloads = downloads
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section("ios-music-service") {
                    LabeledContent("ios-youtube-music", value: account.name ?? String(localized: "ios-guest-mode"))
                    if let handle = account.handle, !handle.isEmpty {
                        LabeledContent("ios-account-channel", value: handle)
                    }
                    if account.name != nil {
                        Button("ios-account-sign-out", role: .destructive) { confirmSignOut = true }
                            .disabled(account.isBusy)
                    } else {
                        Button("ios-account-sign-in") { showSignIn = true }
                            .disabled(account.isBusy || account.isRestoring)
                    }
                    if let error = account.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("ios-retry") { account.retryRestore() }
                            .disabled(account.isBusy || account.isRestoring)
                    }
                    Text("ios-service-description").foregroundStyle(.secondary)
                }

                Section("ios-playback-audio") {
                    Picker("ios-streaming-quality", selection: $settings.streamingQuality) {
                        ForEach(AudioQuality.allCases) { quality in
                            Text(quality.labelKey).tag(quality)
                        }
                    }
                    Picker("ios-download-quality", selection: $settings.downloadQuality) {
                        ForEach(AudioQuality.allCases) { quality in
                            Text(quality.labelKey).tag(quality)
                        }
                    }
                    Toggle("ios-normalize-loudness", isOn: $settings.normalizeVolume)
                    Toggle("ios-autoplay-radio", isOn: $settings.autoplayRadio)
                    Picker("ios-sleep-timer", selection: Binding(
                        get: { settings.sleepTimer },
                        set: { settings.setSleepTimer($0) }
                    )) {
                        ForEach(SleepTimerOption.allCases) { option in
                            Text(option.labelKey).tag(option)
                        }
                    }
                }

                Section("ios-equalizer") {
                    NavigationLink("ios-equalizer") { SoundSettingsView() }
                }

                Section("ios-lyrics") {
                    NavigationLink("ios-lyrics-sources") { LyricsSourcesSettingsView() }
                    Toggle("ios-synced-lyrics", isOn: $settings.syncedLyrics)
                    Toggle("ios-karaoke-lyrics", isOn: $settings.karaokeLyrics)
                    Toggle("ios-backing-vocals", isOn: $settings.backingVocals)
                    LabeledContent("ios-lyrics-text-size", value: settings.lyricsScale.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $settings.lyricsScale, in: 0.5...2, step: 0.05).accessibilityLabel(Text("ios-lyrics-text-size"))
                    Toggle("ios-blur-inactive-lyrics", isOn: $settings.blurInactiveLyrics)
                    Toggle("ios-romanized-lyrics", isOn: $settings.romanizedLyrics)
                    Toggle("ios-local-lyrics", isOn: $settings.localFileLyrics)
                }

                Section("ios-appearance") {
                    NavigationLink("ios-interface-font") { FontSettingsView() }
                    Picker("ios-accent-color", selection: $settings.accent) {
                        ForEach(AppAccent.allCases) { accent in Text(accent.labelKey).tag(accent) }
                    }
                    Picker("ios-theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.labelKey).tag(theme)
                        }
                    }
                    Toggle("ios-animated-artwork", isOn: $settings.animatedArtwork)
                }

                Section {
                    Toggle("ios-cellular-downloads", isOn: $downloads.allowsCellular)
                    LabeledContent("ios-downloads-space", value: formatBytes(downloads.totalBytesUsed))
                    if !downloads.entries.isEmpty {
                        Button("ios-remove-all-downloads", role: .destructive) {
                            confirmRemoveDownloads = true
                        }
                    }
                    LabeledContent("ios-cache-space", value: formatBytes(settings.cacheBytes))
                    Button("ios-clear-cache") { settings.clearCache() }
                } header: {
                    Text("ios-storage-downloads")
                } footer: {
                    Text("ios-cellular-downloads-description")
                }

                Section("ios-scrobbling") {
                    Toggle("ios-scrobble-enable", isOn: $settings.scrobbleEnabled)
                    if settings.pendingScrobbles > 0 {
                        LabeledContent("ios-scrobble-pending", value: settings.pendingScrobbles.formatted())
                        Button("ios-scrobble-retry") { settings.retryScrobbles(force: true) }
                    }
                    if let error = settings.scrobbleError { Text(error).foregroundStyle(.red) }
                    SecureField("ios-listenbrainz-token", text: $settings.listenBrainzToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("ios-maloja-url", text: $settings.malojaURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("ios-maloja-key", text: $settings.malojaKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("ios-about") {
                    LabeledContent("ios-version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("ios-license").foregroundStyle(.secondary)
                }
            }
            .onAppear { settings.measureCache() }
            .sheet(isPresented: $showSignIn) { AccountSignInView() }
            .confirmationDialog("ios-account-sign-out-confirm", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("ios-account-sign-out", role: .destructive) { account.signOut() }
            } message: { Text("ios-account-sign-out-description") }
            .confirmationDialog("ios-remove-all-downloads", isPresented: $confirmRemoveDownloads, titleVisibility: .visible) {
                Button("ios-remove-all-downloads", role: .destructive) { downloads.clearRemoteDownloads() }
            }
            .appNavigationTitle("ios-settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ios-done") { dismiss() } } }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Full-width Apple Music track row with clean trailing ellipsis menu and context menu.
struct TrackRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadsStore.self) private var downloads
    @Environment(SettingsStore.self) private var settings
    @Environment(CatalogStore.self) private var catalog
    @Environment(LocalLibraryStore.self) private var localLibrary
    let track: MusicTrack
    let action: () -> Void
    private var selectionMode = false
    @State private var chooseLocalPlaylist = false
    @State private var confirmLocalDelete = false

    init(track: MusicTrack, action: @escaping () -> Void) { self.track = track; self.action = action }

    /// Makes the existing row a passive label for native multi-selection controls.
    func selecting() -> Self { var row = self; row.selectionMode = true; return row }

    var body: some View {
        Group {
            if selectionMode { trackContent }
            else { playbackRow }
        }
        .sheet(isPresented: $chooseLocalPlaylist) {
            NavigationStack { AddToLocalPlaylistView(trackIDs: [track.id]) }
        }
        .confirmationDialog("ios-delete-from-iphone", isPresented: $confirmLocalDelete, titleVisibility: .visible) {
            Button("ios-delete", role: .destructive) { Task { await library.remove(track) } }
            Button("ios-cancel", role: .cancel) {}
        }
    }

    private var playbackRow: some View {
HStack(spacing: Layout.compact) {
            Button(action: action) { trackContent }
            .buttonStyle(.plain)

            Menu {
                trackMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Layout.control, minHeight: Layout.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ios-track-actions"))
        }
        .contextMenu { trackMenuItems }
    }

    private var trackContent: some View {
HStack(spacing: Layout.spacing) {
                    ArtworkView(track: track, side: Layout.rowArtwork, cornerRadius: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(track.title)
                                .appFont(.body, weight: .medium)
                                .foregroundStyle(playback.current?.id == track.id ? Color.accentColor : Color.primary)
                                .lineLimit(1)
                            if track.explicit {
                                Image(systemName: "e.square.fill")
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(track.artist)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Layout.compact)
                    if track.youtubeID == nil && localLibrary.favoriteTracks.contains(track.id) {
                        Image(systemName: "star.fill").appFont(.caption).foregroundStyle(.tint)
                            .accessibilityLabel(Text("ios-favorite"))
                    }
                    if downloads.entry(for: track.id)?.state == .downloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if playback.current?.id == track.id {
                        Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel(Text("ios-current-track"))
                    }
                }
                .frame(minHeight: Layout.control)
                .contentShape(Rectangle())
    }


    @ViewBuilder
    private var trackMenuItems: some View {
        Button("ios-play-next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            playback.playNext(track)
        }
        Button("ios-add-to-queue", systemImage: "text.badge.plus") {
            playback.addToQueue(track)
        }
        if track.youtubeID == nil {
            LocalTrackActions(track: track) { chooseLocalPlaylist = true }
            Button("ios-delete-from-iphone", systemImage: "trash", role: .destructive) { confirmLocalDelete = true }
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
            if let entry = downloads.entry(for: track.id) {
                if entry.state == .failed {
                    Button("ios-retry", systemImage: "arrow.clockwise") { downloads.retry(track.id) }
                }
                Button("ios-remove-download", systemImage: "trash", role: .destructive) { downloads.remove(track.id) }
            } else {
                Button("ios-download", systemImage: "arrow.down.circle") { downloads.enqueue(track) }
            }
        }
        Button(
            settings.isPinned(track.id) ? "ios-unpin" : "ios-pin",
            systemImage: settings.isPinned(track.id) ? "pin.slash" : "pin"
        ) {
            settings.pinTrack(track)
        }
    }
}

/// Uses the same square artwork treatment for rows, MiniPlayer, and the expanded player.
struct ArtworkView: View {
    let track: MusicTrack?
    let side: CGFloat
    var cornerRadius: CGFloat = Layout.compact
    private let suppliedURL: URL?
    private var symbol = "music.note"

    init(track: MusicTrack?, side: CGFloat, cornerRadius: CGFloat = Layout.compact) {
        self.track = track; self.side = side; self.cornerRadius = cornerRadius; suppliedURL = nil
    }

    init(url: URL?, side: CGFloat, cornerRadius: CGFloat = Layout.compact) {
        track = nil; self.side = side; self.cornerRadius = cornerRadius; suppliedURL = url
    }

    func placeholderSymbol(_ name: String) -> Self { var view = self; view.symbol = name; return view }

    private var artworkURL: URL? { ArtworkRendition.url(suppliedURL ?? track?.displayArtworkURL, side: side) }

    var body: some View {
        ArtworkImage(url: artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
