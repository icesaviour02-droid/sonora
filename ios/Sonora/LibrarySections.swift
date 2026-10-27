import SwiftUI

/// Five primary categories match the reference; Sonora-only collections remain available in Edit.
enum LibraryCategory: String, CaseIterable, Identifiable {
    case playlists, artists, albums, songs, downloads, history, pinned, favorites
    var id: String { rawValue }
    static let defaults = "playlists,artists,albums,songs,downloads"
    var label: LocalizedStringKey {
        switch self {
        case .playlists: "ios-playlists"
        case .artists: "ios-artists"
        case .albums: "ios-albums"
        case .songs: "ios-songs"
        case .downloads: "ios-downloaded-library"
        case .history: "ios-history"
        case .pinned: "ios-pinned"
        case .favorites: "ios-local-favorites"
        }
    }
    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .pinned: "pin"
        case .favorites: "star.fill"
        }
    }
}

/// Category visibility is persisted without deleting any library data or changing playback.
struct LibrarySectionsEditor: View {
    @Binding var visible: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(LibraryCategory.allCases) { category in
                    Toggle(isOn: Binding(get: { visible.split(separator: ",").contains(Substring(category.rawValue)) }, set: { enabled in
                        var values = Set(visible.split(separator: ",").map(String.init))
                        if enabled { values.insert(category.rawValue) } else { values.remove(category.rawValue) }
                        visible = LibraryCategory.allCases.filter { values.contains($0.rawValue) }.map(\.rawValue).joined(separator: ",")
                    })) { Label(category.label, systemImage: category.symbol) }
                }
            }
            .appNavigationTitle("ios-edit-library")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ios-done") { dismiss() } } }
        }
    }
}

extension View {
    /// Explicit insets prevent the standard List padding from inflating the reference's 52 pt rows.
    func libraryCategoryRow() -> some View {
        labelStyle(LibraryCategoryLabelStyle())
            .listRowInsets(EdgeInsets(top: 0, leading: Layout.pageMargin, bottom: 0, trailing: Layout.pageMargin))
            .listRowSeparator(.hidden, edges: .top)
    }
}

extension View {
    /// Song and artist rows share the reference's 48 pt artwork and 56 pt row rhythm.
    func musicListRow() -> some View {
        frame(minHeight: Layout.musicRowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: Layout.pageMargin, bottom: 0, trailing: Layout.pageMargin))
    }
}
