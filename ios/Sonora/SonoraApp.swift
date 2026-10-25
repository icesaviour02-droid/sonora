import SwiftUI

/// Native iPhone entry point, independent of the desktop GPUI runtime.
@main
struct SonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()
    @State private var downloads: DownloadsStore
    @State private var playback: PlaybackController
    @State private var youtube = YouTubeSearch()

    init() {
        let downloads = DownloadsStore()
        _downloads = State(initialValue: downloads)
        _playback = State(initialValue: PlaybackController(downloads: downloads))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(playback)
                .environment(youtube)
                .environment(downloads)
                .task { await library.load() }
        }
    }
}
