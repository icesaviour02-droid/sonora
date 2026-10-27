import SwiftUI

/// Reports the visible spring position so a new drag can interrupt a settling track swipe.
struct PlayerTrackTranslation: AnimatableModifier {
    var offset: CGFloat
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    func body(content: Content) -> some View {
        content.offset(x: offset).preference(key: PlayerTrackPosition.self, value: offset)
    }
}

/// Only the current artwork contributes its presentation position, never the adjacent preview.
struct PlayerTrackPosition: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
