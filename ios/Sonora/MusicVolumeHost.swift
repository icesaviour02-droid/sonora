import MediaPlayer
import UIKit

/// Lays out MPVolumeView through public geometry, keeping speaker symbols on the actual track baseline.
final class MusicVolumeHost: UIView, UIGestureRecognizerDelegate {
    private let volume = MPVolumeView(frame: .zero)
    private let quiet = UIImageView(image: UIImage(systemName: "speaker.fill"))
    private let loud = UIImageView(image: UIImage(systemName: "speaker.wave.3.fill"))
    private var tracking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        volume.showsRouteButton = false
        volume.tintColor = .white
        addSubview(volume)
        for symbol in [quiet, loud] {
            symbol.contentMode = .scaleAspectFit
            symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Layout.volumeSymbolSize)
            symbol.isAccessibilityElement = false
            symbol.isUserInteractionEnabled = false
            addSubview(symbol)
        }
        let touch = UILongPressGestureRecognizer(target: self, action: #selector(touchChanged(_:)))
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delaysTouchesBegan = false
        touch.delaysTouchesEnded = false
        touch.delegate = self
        volume.addGestureRecognizer(touch)
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let expansion = tracking ? Layout.volumeExpansion : 0
        let inset = Layout.volumeTrackInset - expansion
        volume.frame = CGRect(x: inset, y: 0, width: max(0, bounds.width - inset * 2), height: Layout.control)
        volume.layoutIfNeeded()
        let track = volume.volumeSliderRect(forBounds: volume.bounds)
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        let center = track.isEmpty ? Layout.control / 2 : track.midY
        volume.frame.origin.y = ((bounds.midY - center) * scale).rounded() / max(1, scale)
        let side = Layout.volumeSymbolWidth
        quiet.frame = CGRect(x: -expansion, y: bounds.midY - side / 2, width: side, height: side)
        loud.frame = CGRect(x: bounds.maxX - side + expansion, y: bounds.midY - side / 2, width: side, height: side)
    }

    @objc private func touchChanged(_ gesture: UILongPressGestureRecognizer) {
        let active = gesture.state == .began || gesture.state == .changed
        guard tracking != active else { return }
        tracking = active
        applyAppearance()
        setNeedsLayout()
        if UIAccessibility.isReduceMotionEnabled { layoutIfNeeded() }
        else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        }
    }

    /// Custom retina track images resize their solid center only; the native control is never scaled or blurred.
    private func applyAppearance() {
        let height = tracking ? Layout.volumeActiveTrack : Layout.volumeIdleTrack
        for state: UIControl.State in [.normal, .highlighted] {
            volume.setVolumeThumbImage(PlayerSliderImages.idleThumb, for: state)
            volume.setMinimumVolumeSliderImage(PlayerSliderImages.track(alpha: tracking ? 1 : 0.6, height: height), for: state)
            volume.setMaximumVolumeSliderImage(PlayerSliderImages.track(alpha: 0.22, height: height), for: state)
        }
        quiet.tintColor = .white.withAlphaComponent(tracking ? 1 : 0.62)
        loud.tintColor = quiet.tintColor
    }

    /// Observing a drag must leave native hardware-volume tracking and accessibility intact.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
