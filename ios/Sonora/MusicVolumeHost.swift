import MediaPlayer
import UIKit

/// Lays out MPVolumeView through public geometry, keeping speaker symbols on the actual track baseline.
final class MusicVolumeHost: UIView, UIGestureRecognizerDelegate {
    private let volume = MPVolumeView(frame: .zero)
    private let quiet = UIImageView(image: UIImage(systemName: "speaker.fill"))
    private let loud = UIImageView(image: UIImage(systemName: "speaker.wave.3.fill"))
    private var tracking = false
    private var activation: CGFloat = 0
    private var fromActivation: CGFloat = 0
    private var targetActivation: CGFloat = 0
    private var beganAt: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private lazy var ticker = Ticker(self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        volume.showsRouteButton = false
        volume.tintColor = .white
        addSubview(volume)
        for symbol in [quiet, loud] {
            symbol.contentMode = .center
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
        let expansion = activation * Layout.volumeExpansion
        let inset = Layout.volumeTrackInset - expansion
        volume.frame = CGRect(x: inset, y: 0, width: max(0, bounds.width - inset * 2), height: Layout.control)
        volume.layoutIfNeeded()
        let track = volume.volumeSliderRect(forBounds: volume.bounds)
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        // MPVolumeView documents its slider as UISlider. Read the public track rectangle rather
        // than assuming the drawing rectangle and UISlider's own baseline are identical.
        let nativeSlider = volume.subviews.compactMap { $0 as? UISlider }.first
        let actualTrack = nativeSlider.map { $0.convert($0.trackRect(forBounds: $0.bounds), to: volume) }
        let center = actualTrack?.midY ?? (track.isEmpty ? Layout.control / 2 : track.midY)
        volume.frame.origin.y = ((bounds.midY - center) * scale).rounded() / max(1, scale)
        let side = Layout.volumeSymbolWidth
        quiet.frame = CGRect(x: -expansion, y: bounds.midY - side / 2, width: side, height: side)
        loud.frame = CGRect(x: bounds.maxX - side + expansion, y: bounds.midY - side / 2, width: side, height: side)
    }

    @objc private func touchChanged(_ gesture: UILongPressGestureRecognizer) {
        let active = gesture.state == .began || gesture.state == .changed
        guard tracking != active else { return }
        tracking = active
        fromActivation = activation; targetActivation = active ? 1 : 0
        beganAt = CACurrentMediaTime()
        displayLink?.invalidate(); displayLink = nil
        if UIAccessibility.isReduceMotionEnabled {
            activation = targetActivation; applyAppearance(); setNeedsLayout()
        } else {
            let link = CADisplayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    /// Each frame changes native track assets and geometry together, keeping retina edges sharp.
    private func step(_ link: CADisplayLink) {
        let elapsed = max(0, link.timestamp - beganAt)
        let progress = min(1, elapsed / Layout.volumeResponse)
        let eased = 1 - pow(1 - progress, 3)
        activation = fromActivation + (targetActivation - fromActivation) * eased
        applyAppearance(); setNeedsLayout(); layoutIfNeeded()
        if progress >= 1 { link.invalidate(); displayLink = nil }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate(); displayLink = nil
            tracking = false; activation = 0; applyAppearance()
        }
    }
    private final class Ticker: NSObject {
        weak var owner: MusicVolumeHost?
        init(_ owner: MusicVolumeHost) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.step(link) }
    }

    /// Custom retina track images resize their solid center only; the native control is never scaled or blurred.
    private func applyAppearance() {
        let height = Layout.volumeIdleTrack + (Layout.volumeActiveTrack - Layout.volumeIdleTrack) * activation
        for state: UIControl.State in [.normal, .highlighted] {
            volume.setVolumeThumbImage(PlayerSliderImages.idleThumb, for: state)
            volume.setMinimumVolumeSliderImage(PlayerSliderImages.track(alpha: 0.6 + 0.4 * activation, height: height), for: state)
            volume.setMaximumVolumeSliderImage(PlayerSliderImages.track(alpha: 0.22, height: height), for: state)
        }
        quiet.tintColor = .white.withAlphaComponent(0.62 + 0.38 * activation)
        loud.tintColor = quiet.tintColor
    }

    /// Observing a drag must leave native hardware-volume tracking and accessibility intact.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
