import SwiftUI

/// Native iPhone entry point, independent of the desktop GPUI runtime.
@main
struct SonoraApp: App {
    @State private var library = LibraryStore()
    @State private var playback = PlaybackController()
    @State private var youtube = YouTubeSearch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(playback)
                .environment(youtube)
                .task { await library.load() }
        }
    }
}
