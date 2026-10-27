import Foundation

/// Stable locale-aware groups shared by library and downloaded music indexes.
struct AlphabeticGroup<Item>: Identifiable {
    let id: String
    let items: [Item]
}

/// Groups punctuation and numeric titles under # and folds accents for letter navigation.
enum LibraryAlphabet {
    static func groups<Item>(_ items: [Item], title: (Item) -> String) -> [AlphabeticGroup<Item>] {
        let sorted = items.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
        let groups = Dictionary(grouping: sorted) { item in
            let name = title(item).trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            guard let first = name.first, first.isLetter else { return "#" }
            return String(first).uppercased(with: .current)
        }
        return groups.keys.sorted {
            if $0 == "#" { return false }
            if $1 == "#" { return true }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }.map { AlphabeticGroup(id: $0, items: groups[$0] ?? []) }
    }
}
