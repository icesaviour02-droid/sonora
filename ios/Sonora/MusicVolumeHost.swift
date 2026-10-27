import MediaPlayer
import UIKit

/// Uses the standard system-volume control without custom assets, scaling, tracking gestures or external icons.
final class MusicVolumeHost: UIView {
    private let volume = MPVolumeView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        volume.showsRouteButton = false
        volume.tintColor = .white
        volume.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        volume.accessibilityIdentifier = "player-system-volume"
        addSubview(volume)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        volume.frame = bounds
    }
}
