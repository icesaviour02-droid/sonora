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
        slider.setThumbImage(PlayerSliderImages.idleThumb, for: .normal)
        slider.setThumbImage(PlayerSliderImages.trackingThumb, for: .highlighted)
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
    final class SeekControl: UISlider {
        var editingChanged: ((Bool) -> Void)?
        private(set) var scrubbing = false
        override func trackRect(forBounds bounds: CGRect) -> CGRect {
            CGRect(x: bounds.minX, y: bounds.midY - Layout.playerSliderTrack / 2,
                width: bounds.width, height: Layout.playerSliderTrack)
        }
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            guard isEnabled else { return false }
            scrubbing = true
            isHighlighted = true
            editingChanged?(true)
            updateValue(touch)
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            updateValue(touch)
            return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { updateValue(touch) }
            scrubbing = false
            isHighlighted = false
            editingChanged?(false)
        }
        override func cancelTracking(with event: UIEvent?) {
            scrubbing = false
            isHighlighted = false
            editingChanged?(false)
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
        let side = height
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            UIColor.white.withAlphaComponent(alpha).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: side / 3, bottom: 0, right: side / 3))
    }
}
