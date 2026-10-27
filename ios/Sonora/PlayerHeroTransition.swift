import Observation
import SwiftUI
import UIKit

/// Carries one cover above the fullscreen transition, including its interactive cancellation path.
@MainActor @Observable final class PlayerHeroState {
    private(set) var coversHidden = false
    @ObservationIgnored private weak var mini: UIView?
    @ObservationIgnored private weak var expanded: UIView?
    @ObservationIgnored private var cover: UIImageView?
    @ObservationIgnored private var image: UIImage?
    @ObservationIgnored private var sourceRect: CGRect = .zero
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var animating = false
    @ObservationIgnored private var prepareTask: Task<Void, Never>?

    func register(_ view: UIView, role: PlayerHeroAnchor.Role) {
        switch role {
        case .mini: mini = view
        case .expanded: expanded = view
        }
    }

    /// Capture before the native presenter scales its underlying content.
    func prepareOpening(image: UIImage?) {
        guard !UIAccessibility.isReduceMotionEnabled, let mini, let window = mini.window else { return }
        finish()
        sourceRect = mini.convert(mini.bounds, to: window)
        guard !sourceRect.isEmpty else { return }
        self.image = image ?? snapshot(in: window, rect: sourceRect)
        guard let image = self.image else { return }
        opening = true
        self.image = image
        prepareTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.opening, !self.animating else { return }
            self.finish()
        }
    }

    /// The same native interactive animator interpolates the panel and cover with no independent timing.
    func beginFlight(opening: Bool, in container: UIView) -> (() -> Void)? {
        guard !UIAccessibility.isReduceMotionEnabled, let mini, let expanded,
              let window = expanded.window, mini.window === window else { finish(); return nil }
        let large = expanded.convert(expanded.bounds, to: window)
        let small = opening && !sourceRect.isEmpty ? sourceRect : mini.convert(mini.bounds, to: window)
        guard !large.isEmpty, !small.isEmpty,
              let image = image ?? snapshot(in: window, rect: opening ? small : large) else { finish(); return nil }
        finish()
        install(image: image, rect: opening ? small : large,
            radius: opening ? Layout.miniArtworkRadius : Layout.artworkRadius, in: window)
        animating = true
        let destination = opening ? large : small
        guard let cover else { return nil }
        return { cover.frame = destination; cover.layer.cornerRadius = opening ? Layout.artworkRadius : Layout.miniArtworkRadius }
    }

    func improveImage(_ image: UIImage?) {
        guard let image else { return }
        self.image = image
        cover?.image = image
    }

    func finish() {
        prepareTask?.cancel(); prepareTask = nil
        cover?.removeFromSuperview(); cover = nil
        opening = false; animating = false; sourceRect = .zero
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { coversHidden = false }
    }

    private func install(image: UIImage, rect: CGRect, radius: CGFloat, in window: UIWindow) {
        let view = UIImageView(image: image)
        view.frame = rect; view.contentMode = .scaleAspectFill; view.clipsToBounds = true
        view.layer.cornerRadius = radius; view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        window.addSubview(view); cover = view
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { coversHidden = true }
    }

    /// A fallback captures only the cover rectangle; normal playback supplies a shared high-resolution image.
    private func snapshot(in window: UIWindow, rect: CGRect) -> UIImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return UIGraphicsImageRenderer(size: rect.size).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            window.layer.render(in: context.cgContext)
        }
    }
}

/// Invisible anchors measure the actual native accessory and player cover in the same window.
struct PlayerHeroAnchor: UIViewRepresentable {
    enum Role { case mini, expanded }
    let hero: PlayerHeroState
    let role: Role
    func makeUIView(context: Context) -> Anchor { Anchor(hero: hero, role: role) }
    func updateUIView(_ view: Anchor, context: Context) { view.report() }

    final class Anchor: UIView {
        weak var hero: PlayerHeroState?
        let role: Role
        init(hero: PlayerHeroState, role: Role) {
            self.hero = hero; self.role = role
            super.init(frame: .zero); isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() { guard window != nil, bounds.width > 0 else { return }; hero?.register(self, role: role) }
    }
}
