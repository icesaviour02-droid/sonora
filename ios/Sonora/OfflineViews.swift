import SwiftUI

/// Offline Home routes to actual device content instead of issuing failing provider requests.
struct OfflineHomeView: View {
    let openDownloads: () -> Void
    let openSettings: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("ios-offline-active", systemImage: "wifi.slash")
        } description: {
            Text("ios-offline-home-description")
        } actions: {
            Button("ios-open-downloads", action: openDownloads).buttonStyle(.glass)
        }
        .appNavigationTitle("ios-home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios-settings", systemImage: "gearshape", action: openSettings)
            }
        }
    }
}

/// The Search tab remains useful offline by filtering saved music without contacting providers.
struct OfflineSearchView: View {
    @State private var query = ""
    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("ios-offline-active", systemImage: "wifi.slash", description: Text("ios-offline-home-description"))
            } else { MusicPageSearchResults(query: query, offlineOnly: true) }
        }
        .appNavigationTitle("ios-search")
        .collectionSearch(text: $query)
    }
}
