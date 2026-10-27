import SwiftUI
import UIKit

/// One visible title/artist layer moves between presentations without cross-fading duplicate labels.
struct AnimatedPlayerMetadata: View, Animatable {
    let title: String
    let artist: String
    var titleSize: CGFloat
    var artistSize: CGFloat
    var spacing: CGFloat
    let expandedAccessibility: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(titleSize, artistSize), spacing) }
        set { titleSize = newValue.first.first; artistSize = newValue.first.second; spacing = newValue.second }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            FadingText(title, fixedPointSize: titleSize, weight: .semibold,
                color: .white, lines: expandedAccessibility ? 3 : 1, fadeTail: false)
            FadingText(artist, fixedPointSize: artistSize,
                color: UIColor.white.withAlphaComponent(0.7), lines: expandedAccessibility ? 2 : 1, fadeTail: false)
        }
    }
}
