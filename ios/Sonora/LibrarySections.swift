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

/// Inline check circles share the Library's row identity while native edit mode supplies reorder handles.
struct LibraryCategoryEditingRow: View {
    let category: LibraryCategory
    let selected: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Layout.compact) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .appFont(.body).frame(width: Layout.categoryIcon)
                Label(category.label, systemImage: category.symbol)
                    .labelStyle(LibraryCategoryLabelStyle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("library-category-" + category.rawValue)
    }
}

extension LibraryCategory {
    /// Retain saved order and append new categories without dropping a valid existing selection.
    static func ordered(_ value: String) -> [LibraryCategory] {
        var seen: Set<LibraryCategory> = []
        return (value.split(separator: ",").compactMap { LibraryCategory(rawValue: String($0)) } + allCases)
            .filter { seen.insert($0).inserted }
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
