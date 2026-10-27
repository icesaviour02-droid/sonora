import SwiftUI
import UIKit

/// Single-line metadata keeps its natural glyphs and fades only when the available width clips it.
struct FadingText: UIViewRepresentable {
    @Environment(\.appTypeface) private var typeface
    @ScaledMetric private var pointSize: CGFloat
    let text: String
    let weight: UIFont.Weight
    let color: UIColor
    private let fixedPointSize: CGFloat?
    private let lines: Int
    private let fadeTail: Bool

    init(_ text: String, style: Font.TextStyle, weight: UIFont.Weight = .regular, color: UIColor = .label) {
        self.text = text; self.weight = weight; self.color = color
        self.fixedPointSize = nil; self.lines = 1; self.fadeTail = true
        _pointSize = ScaledMetric(wrappedValue: InterfaceTypography.baselineSize(style), relativeTo: style)
    }

    /// Already-scaled values allow the player to interpolate text size with its cover geometry.
    init(_ text: String, fixedPointSize: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .label, lines: Int = 1, fadeTail: Bool = true) {
        self.text = text; self.weight = weight; self.color = color
        self.fixedPointSize = fixedPointSize; self.lines = lines; self.fadeTail = fadeTail
        _pointSize = ScaledMetric(wrappedValue: fixedPointSize, relativeTo: .body)
    }

    func makeUIView(context: Context) -> TailFadingLabel {
        let label = TailFadingLabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: TailFadingLabel, context: Context) {
        let pointSize = fixedPointSize ?? self.pointSize
        label.fadesOverflow = fadeTail
        label.numberOfLines = lines
        label.lineBreakMode = lines == 1 ? .byClipping : .byWordWrapping
        let system = UIFont.systemFont(ofSize: pointSize, weight: weight)
        if typeface == "rounded", let rounded = system.fontDescriptor.withDesign(.rounded) {
            label.font = UIFont(descriptor: rounded, size: pointSize)
        } else if typeface != "system", typeface != "rounded", let custom = UIFont(name: typeface, size: pointSize) {
            label.font = UIFont(descriptor: custom.fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]
            ]), size: pointSize)
        } else { label.font = system }
        label.text = text
        label.textColor = color
        label.accessibilityLabel = text
        label.invalidateIntrinsicContentSize()
        label.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TailFadingLabel, context: Context) -> CGSize? {
        let natural = uiView.intrinsicContentSize
        let width = proposal.width ?? natural.width
        let fittedWidth = width.isFinite ? max(0, width) : natural.width
        let height = lines == 1 ? natural.height : uiView.sizeThatFits(CGSize(width: fittedWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: fittedWidth, height: height)
    }
}

/// A GPU alpha mask follows native layout and the reading direction; short text never fades.
final class TailFadingLabel: UILabel {
    private let fade = CAGradientLayer()
    var fadesOverflow = true

    override func layoutSubviews() {
        super.layoutSubviews()
        guard fadesOverflow, numberOfLines == 1, bounds.width > 0, intrinsicContentSize.width > bounds.width else { layer.mask = nil; return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        fade.startPoint = CGPoint(x: rtl ? 1 : 0, y: 0.5)
        fade.endPoint = CGPoint(x: rtl ? 0 : 1, y: 0.5)
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: max(0, 1 - Layout.metadataFade / bounds.width)), 1]
        layer.mask = fade
        CATransaction.commit()
    }
}

/// Player changes retarget a non-bouncy spring instead of waiting for a prescribed sequence.
enum PlayerMotion {
    static let mode = Animation.spring(response: 0.4, dampingFraction: 1)
    static let artworkScale = Animation.spring(response: 0.48, dampingFraction: 1)
    static let libraryEdit = Animation.spring(response: 0.32, dampingFraction: 1)
    static let trackSwipe = Animation.spring(response: 0.32, dampingFraction: 1)
    static let press = Animation.spring(response: 0.2, dampingFraction: 1)
}

/// Press feedback begins at touch-down and remains cancelable while a finger moves off a control.
struct PlayerControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : PlayerMotion.press, value: configuration.isPressed)
    }
}
