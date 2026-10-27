import SwiftUI
import UIKit

/// Native slider input with Music's thin idle track, a tracking thumb and a full touch target.
@MainActor struct MusicSeekSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> SeekControl {
        let slider = SeekControl()
        slider.minimumTrackTintColor = .white.withAlphaComponent(0.6)
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.2)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        let coordinator = context.coordinator
        slider.editingChanged = { [weak coordinator] editing in coordinator?.parent.onEditingChanged(editing) }
        return slider
    }

    func updateUIView(_ slider: SeekControl, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.isEnabled = context.environment.isEnabled
        if !slider.scrubbing { slider.setValue(Float(value), animated: false) }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: MusicSeekSlider
        init(parent: MusicSeekSlider) { self.parent = parent }
        @objc func changed(_ slider: SeekControl) {
            // VoiceOver adjusts a slider without beginning a finger-tracking session.
            if !slider.scrubbing { parent.onEditingChanged(true) }
            parent.value = Double(slider.value)
            if !slider.scrubbing { parent.onEditingChanged(false) }
        }
    }

    /// Any point on the 44 pt control can start a seek; progress follows the finger continuously.
    final class SeekControl: UIControl {
        var editingChanged: ((Bool) -> Void)?
        private(set) var scrubbing = false
        var minimumValue: Float = 0
        var maximumValue: Float = 1
        private(set) var value: Float = 0
        var minimumTrackTintColor: UIColor = .white
        var maximumTrackTintColor: UIColor = .white.withAlphaComponent(0.2)
        private let backgroundTrack = CALayer()
        private let progressTrack = CALayer()
        private let thumb = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            for item in [backgroundTrack, progressTrack, thumb] { layer.addSublayer(item) }
            isAccessibilityElement = true
            accessibilityTraits = .adjustable
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setValue(_ value: Float, animated: Bool) {
            self.value = min(maximumValue, max(minimumValue, value))
            accessibilityValue = Double(fraction).formatted(.percent.precision(.fractionLength(0)))
            setNeedsLayout()
        }
        private var fraction: CGFloat { CGFloat((value - minimumValue) / max(maximumValue - minimumValue, .ulpOfOne)) }
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let height = Layout.playerSliderTrack
            let track = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
            backgroundTrack.frame = track; backgroundTrack.cornerRadius = height / 2
            backgroundTrack.backgroundColor = maximumTrackTintColor.cgColor
            progressTrack.frame = CGRect(x: track.minX, y: track.minY, width: track.width * fraction, height: height)
            progressTrack.cornerRadius = height / 2; progressTrack.backgroundColor = minimumTrackTintColor.cgColor
            let side = Layout.sliderTrackingThumb
            thumb.frame = CGRect(x: track.width * fraction - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            thumb.cornerRadius = side / 2; thumb.backgroundColor = UIColor.white.cgColor
            thumb.isHidden = !scrubbing
            CATransaction.commit()
        }
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            guard isEnabled else { return false }
            scrubbing = true
            editingChanged?(true)
            updateValue(touch)
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            updateValue(touch); return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { updateValue(touch) }
            scrubbing = false; setNeedsLayout(); editingChanged?(false)
        }
        override func cancelTracking(with event: UIEvent?) {
            scrubbing = false; setNeedsLayout(); editingChanged?(false)
        }
        override func accessibilityIncrement() { adjust(1) }
        override func accessibilityDecrement() { adjust(-1) }
        private func adjust(_ direction: Float) {
            guard isEnabled else { return }
            setValue(value + direction * max(1, (maximumValue - minimumValue) / 20), animated: false)
            sendActions(for: .valueChanged)
        }
        private func updateValue(_ touch: UITouch) {
            let fraction = min(1, max(0, touch.location(in: self).x / max(bounds.width, 1)))
            setValue(minimumValue + Float(fraction) * (maximumValue - minimumValue), animated: false)
            sendActions(for: .valueChanged)
        }
    }
}

/// Public MPVolumeView image hooks share the same lightweight track without replacing system volume.
@MainActor enum PlayerSliderImages {
    static let idleThumb = UIGraphicsImageRenderer(size: CGSize(width: Layout.sliderIdleThumb, height: Layout.sliderIdleThumb))
        .image { _ in }
    static let trackingThumb = UIGraphicsImageRenderer(size: CGSize(width: Layout.sliderTrackingThumb, height: Layout.sliderTrackingThumb))
        .image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: Layout.sliderTrackingThumb, height: Layout.sliderTrackingThumb))
        }
    static func track(alpha: CGFloat, height: CGFloat = Layout.playerSliderTrack) -> UIImage {
        let size = CGSize(width: height * 2 + 1, height: height)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.withAlphaComponent(alpha).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height, bottom: 0, right: height), resizingMode: .stretch)
    }
}
