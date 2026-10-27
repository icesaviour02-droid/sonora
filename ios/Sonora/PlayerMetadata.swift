import SwiftUI
import UIKit

/// One visible title/artist layer moves between presentations without cross-fading duplicate labels.
struct AnimatedPlayerMetadata: View, Animatable {
    let title: String
    let artist: String
    var titleSize: CGFloat
    let artistSize: CGFloat
    var spacing: CGFloat
    let expandedAccessibility: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(titleSize, spacing) }
        set { titleSize = newValue.first; spacing = newValue.second }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            FadingText(title, fixedPointSize: titleSize, weight: .semibold,
                color: .white, lines: expandedAccessibility ? 3 : 1)
            FadingText(artist, fixedPointSize: artistSize,
                color: UIColor.white.withAlphaComponent(0.7), lines: expandedAccessibility ? 2 : 1)
        }
    }
}
