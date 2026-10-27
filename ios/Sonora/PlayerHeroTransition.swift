import Observation
import SwiftUI
import UIKit

/// The cover stays in its rounded player until a committed dismissal reaches its final handoff region.
@MainActor @Observable final class PlayerHeroState {
    @ObservationIgnored private(set) weak var pillView: UIView?
    @ObservationIgnored private weak var mini: PlayerArtworkVisual.Node?
    @ObservationIgnored private weak var expanded: PlayerArtworkVisual.Node?
    @ObservationIgnored private weak var surface: UIView?
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private var overlay: UIImageView?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var waitingForRelease = false
    @ObservationIgnored private var thresholdY: CGFloat = 0
    @ObservationIgnored private var lastY: CGFloat = 0
    @ObservationIgnored private var height: CGFloat = 1
    @ObservationIgnored private var coverRect: CGRect = .zero
    @ObservationIgnored private var handedOff = false
    @ObservationIgnored private lazy var ticker = Ticker(self)

    func register(_ view: UIView) { pillView = view }
    func register(_ view: PlayerArtworkVisual.Node, role: PlayerArtworkVisual.Role) {
        if role == .mini { mini = view } else { expanded = view }
    }

    /// Record actual source/target bounds before UIKit translates the complete player surface.
    func begin(surface: UIView, opening: Bool, interactive: Bool) {
        finish()
        guard !UIAccessibility.isReduceMotionEnabled, let expanded, !expanded.isPlaceholder, let mini,
              let window = surface.window, expanded.window === window, mini.window === window else { return }
        let rect = expanded.convert(expanded.bounds, to: window)
        guard !rect.isEmpty else { return }
        self.surface = surface; self.window = window; self.opening = opening
        coverRect = rect; height = max(1, surface.bounds.height)
        thresholdY = height * Layout.playerCoverHandoffStart
        lastY = opening ? height : 0
        waitingForRelease = interactive && !opening
        let image = UIImageView(image: expanded.artwork)
        image.contentMode = .scaleAspectFill; image.clipsToBounds = true
        image.isUserInteractionEnabled = false; image.isAccessibilityElement = false; image.alpha = 0
        image.tintColor = expanded.imageView.tintColor
        window.addSubview(image); overlay = image
        let link = CADisplayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
        displayLink = link; link.add(to: .main, forMode: .common)
        update(y: lastY)
    }

    /// Crossing the threshold while the finger is down never detaches the artwork.
    func release(committing: Bool) {
        guard !opening else { return }
        waitingForRelease = !committing
        if committing { thresholdY = max(height * Layout.playerCoverHandoffStart, currentY()) }
    }

    private func currentY() -> CGFloat {
        if let value = surface?.layer.presentation()?.affineTransform().ty { lastY = value }
        return min(height, max(0, lastY))
    }
    private func tick() { update(y: currentY()) }

    private func update(y: CGFloat) {
        guard let overlay, let expanded, let mini, let window else { return }
        let progress = min(1, max(0, (y - thresholdY) / max(1, height - thresholdY)))
        guard !waitingForRelease, y >= thresholdY else {
            overlay.alpha = 0; expanded.alpha = 1; mini.alpha = 1
            return
        }
        let start = coverRect.offsetBy(dx: 0, dy: thresholdY)
        let target = mini.convert(mini.bounds, to: window)
        guard !target.isEmpty else { return }
        // Use the panel's visible displacement, so interactive cancellation and the image cannot desynchronize.
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        overlay.image = expanded.artwork
        overlay.frame = CGRect(x: mix(start.minX, target.minX), y: mix(start.minY, target.minY),
            width: mix(start.width, target.width), height: mix(start.height, target.height))
        overlay.layer.cornerRadius = mix(expanded.radius, mini.radius)
        overlay.alpha = 1; expanded.alpha = 0; mini.alpha = 0
        CATransaction.commit()
        if !handedOff { handedOff = true; record("handoff") }
    }

    /// Restore the real UIKit images synchronously; no SwiftUI opacity update or delayed return jump is needed.
    func finish() {
        displayLink?.invalidate(); displayLink = nil
        overlay?.removeFromSuperview(); overlay = nil
        expanded?.alpha = 1; mini?.alpha = 1
        if handedOff { record("restored") }
        surface = nil; window = nil; handedOff = false; waitingForRelease = false
    }
    private func record(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--sonora-review-fullscreen") else { return }
        let url = URL.applicationSupportDirectory.appendingPathComponent("player-cover-handoff-review.json")
        var events = ((try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [[String: Any]] ?? []
        events.append(["event": event, "opening": opening, "afterRelease": !waitingForRelease, "threshold": thresholdY / height,
            "miniWidth": mini?.bounds.width ?? 0, "coverWidth": coverRect.width,
            "sourceAlpha": expanded?.alpha ?? 1, "miniAlpha": mini?.alpha ?? 1])
        if let data = try? JSONSerialization.data(withJSONObject: Array(events.suffix(12))) { try? data.write(to: url, options: .atomic) }
        #endif
    }
    @MainActor private final class Ticker: NSObject {
        weak var hero: PlayerHeroState?
        init(_ hero: PlayerHeroState) { self.hero = hero }
        @objc func tick(_ link: CADisplayLink) { hero?.tick() }
    }
}

/// Both real cover nodes share the player's high-resolution image; UIKit controls visibility during the final handoff.
struct PlayerArtworkVisual: UIViewRepresentable {
    enum Role: Equatable { case mini, expanded }
    let image: UIImage?
    let hero: PlayerHeroState?
    let role: Role
    let radius: CGFloat
    var shadowOpacity: Float = 0
    var shadowRadius: CGFloat = 0
    var shadowOffset: CGFloat = 0

    func makeUIView(context: Context) -> Node { Node() }
    func updateUIView(_ view: Node, context: Context) {
        view.hero = hero; view.role = role; view.radius = radius
        view.isPlaceholder = image == nil
        view.artwork = image ?? UIImage(systemName: "music.note")
        view.imageView.image = view.artwork
        view.imageView.contentMode = image == nil ? .center : .scaleAspectFill
        view.imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: role == .mini ? Layout.miniTitleSize : Layout.playerPlaySymbol)
        view.imageView.tintColor = .secondaryLabel
        view.imageView.backgroundColor = image == nil ? .tertiarySystemFill : .clear
        view.layer.shadowColor = UIColor.black.cgColor; view.layer.shadowOpacity = shadowOpacity
        view.layer.shadowRadius = shadowRadius; view.layer.shadowOffset = CGSize(width: 0, height: shadowOffset)
        view.setNeedsLayout(); view.report()
    }
    final class Node: UIView {
        weak var hero: PlayerHeroState?
        var role = Role.expanded
        var radius: CGFloat = 0
        var artwork: UIImage?
        var isPlaceholder = true
        let imageView = UIImageView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false; isAccessibilityElement = false
            imageView.clipsToBounds = true; addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            imageView.frame = bounds; imageView.layer.cornerRadius = radius
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
            CATransaction.commit(); report()
        }
        func report() { guard window != nil, bounds.width > 0 else { return }; hero?.register(self, role: role) }
    }
}

/// The accessory's outer frame remains available for transition geometry across tab minimization.
struct PlayerHeroAnchor: UIViewRepresentable {
    let hero: PlayerHeroState
    func makeUIView(context: Context) -> Anchor { Anchor(hero: hero) }
    func updateUIView(_ view: Anchor, context: Context) { view.report() }
    final class Anchor: UIView {
        weak var hero: PlayerHeroState?
        init(hero: PlayerHeroState) {
            self.hero = hero; super.init(frame: .zero)
            isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() { guard window != nil, bounds.width > 0 else { return }; hero?.register(self) }
    }
}
