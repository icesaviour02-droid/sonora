import SwiftUI

/// Native iPhone entry point, independent of the desktop GPUI runtime.
@main
struct SonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()
    @State private var library = LibraryStore()
    @State private var settings: SettingsStore
    @State private var downloads: DownloadsStore
    @State private var playback: PlaybackController
    @State private var youtube = YouTubeSearch()
    @State private var catalog = CatalogStore()
    @State private var fonts = FontLibrary()
    @State private var appearance = AppearanceStore()
    @State private var poTokenMinter = PoTokenMinter()

    init() {
        let settings = SettingsStore()
        let downloads = DownloadsStore()
        _settings = State(initialValue: settings)
        _downloads = State(initialValue: downloads)
        _playback = State(initialValue: PlaybackController(downloads: downloads, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(account)
                .environment(library)
                .environment(settings)
                .environment(playback)
                .environment(youtube)
                .environment(downloads)
                .environment(catalog)
                .environment(fonts)
                .environment(\.appTypeface, settings.typefaceID)
                .fontDesign(settings.typefaceID == "rounded" ? .rounded : .default)
                .font(InterfaceTypography.font(.body, typeface: settings.typefaceID))
                .tint(appearance.color(for: settings.accent))
                .onChange(of: playback.current?.artworkURL, initial: true) { _, url in
                    appearance.updateArtwork(url)
                }
                .task {
                    poTokenMinter.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        downloads.resumeQueue()
                        account.rotateCookiesIfSignedIn()
                    }
                }
        }
    }
}
