import Foundation

/// Keeps container padding out of the song clock. A resolved stream duration is more precise
/// than catalog labels; old downloads use the catalog only for a clearly doubled container.
enum PlaybackTimeline {
    static func end(native: Double?, audioEnd: Double?, source: Double?, catalog: Double?) -> Double? {
        func valid(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        let container = valid(native)
        let audio = valid(audioEnd)
        let media = [container, audio].compactMap { $0 }.min()
        if let source = valid(source) { return media.map { min($0, source) } ?? source }
        if let catalog = valid(catalog), let media,
           media > catalog * 1.5, media < catalog * 2.5 {
            return catalog
        }
        return media ?? valid(catalog)
    }
}
