import Observation
import SwiftUI
import UIKit

/// Carries one cover above the native sheet transition, including its interactive cancellation path.
@MainActor @Observable final class PlayerHeroState {
    private(set) var coversHidden = false
    @ObservationIgnored private weak var mini: UIView?
    @ObservationIgnored private weak var expanded: UIView?
    @ObservationIgnored private var cover: UIImageView?
    @ObservationIgnored private var image: UIImage?
    @ObservationIgnored private var sourceRect: CGRect = .zero
    @ObservationIgnored private var openingCoordinator: (any UIViewControllerTransitionCoordinator)?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var animating = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var coordinatorGeneration: UUID?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?

    func register(_ view: UIView, role: PlayerHeroAnchor.Role) {
        switch role {
        case .mini: mini = view
        case .expanded: expanded = view; animateOpeningIfReady()
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
        install(image: image, rect: sourceRect, radius: Layout.miniArtworkRadius, in: window)
        prepareTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.opening, !self.animating else { return }
            self.finish()
        }
    }

    func opening(with coordinator: (any UIViewControllerTransitionCoordinator)?, image: UIImage?) {
        if !opening { prepareOpening(image: image) }
        openingCoordinator = coordinator
        animateOpeningIfReady()
    }

    private func animateOpeningIfReady() {
        guard opening, !animating, let cover, let expanded, let window = expanded.window else { return }
        let target = expanded.convert(expanded.bounds, to: window)
        guard target.width > Layout.control, target.height > Layout.control else { return }
        animating = true
        prepareTask?.cancel(); prepareTask = nil
        let token = generation
        let changes: () -> Void = { cover.frame = target; cover.layer.cornerRadius = Layout.artworkRadius }
        if let coordinator = openingCoordinator {
            coordinatorGeneration = token
            let queued = coordinator.animateAlongsideTransition(in: window, animation: { _ in changes() }, completion: { [weak self] _ in
                guard let self, self.generation == token, self.coordinatorGeneration == token else { return }; self.finish()
            })
            if queued { return }
            coordinatorGeneration = nil
        }
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) { [weak self] _ in
                guard let self, self.generation == token else { return }; self.finish()
            }
    }

    /// UIKit's coordinator drives the same cover when a sheet drag finishes or reverses.
    func closing(with coordinator: (any UIViewControllerTransitionCoordinator)?, image: UIImage?) {
        guard !UIAccessibility.isReduceMotionEnabled, let mini, let expanded,
              let window = expanded.window, mini.window === window else { finish(); return }
        let start = expanded.convert(expanded.bounds, to: window)
        let target = mini.convert(mini.bounds, to: window)
        guard !start.isEmpty, !target.isEmpty,
              let image = image ?? snapshot(in: window, rect: start) ?? self.image else { finish(); return }
        finish()
        install(image: image, rect: start, radius: Layout.artworkRadius, in: window)
        guard let cover else { return }
        animating = true
        prepareTask?.cancel(); prepareTask = nil
        let token = generation
        let changes: () -> Void = { cover.frame = target; cover.layer.cornerRadius = Layout.miniArtworkRadius }
        if let coordinator {
            coordinatorGeneration = token
            let queued = coordinator.animateAlongsideTransition(in: window, animation: { _ in changes() }, completion: { [weak self] _ in
                guard let self, self.generation == token, self.coordinatorGeneration == token else { return }; self.finish()
            })
            if queued { return }
            coordinatorGeneration = nil
        }
        UIView.animate(withDuration: 0.4, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) { [weak self] _ in
            guard let self, self.generation == token else { return }; self.finish()
        }
    }

    func improveImage(_ image: UIImage?) {
        guard let image else { return }
        self.image = image
        cover?.image = image
    }

    func finishIfNotAnimating() { if !animating { finish() } }
    func finish() {
        generation = UUID(); coordinatorGeneration = nil
        prepareTask?.cancel(); prepareTask = nil
        cover?.removeFromSuperview(); cover = nil
        opening = false; animating = false; openingCoordinator = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { coversHidden = false }
    }

    private func install(image: UIImage, rect: CGRect, radius: CGFloat, in window: UIWindow) {
        generation = UUID()
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

/// Observes the sheet's real transition coordinator without replacing native modal gestures or menus.
struct PlayerHeroObserver: UIViewControllerRepresentable {
    let hero: PlayerHeroState
    let image: UIImage?
    func makeUIViewController(context: Context) -> Controller { Controller(hero: hero, image: image) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.image = image; hero.improveImage(image) }

    final class Controller: UIViewController {
        let hero: PlayerHeroState
        var image: UIImage?
        private var appeared = false
        init(hero: PlayerHeroState, image: UIImage?) { self.hero = hero; self.image = image; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        private var sheet: UIViewController? {
            var candidate: UIViewController? = self
            var result: UIViewController?
            while let value = candidate {
                if value.presentingViewController != nil { result = value }
                candidate = value.parent
            }
            return result
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !appeared else { return }
            hero.opening(with: sheet?.transitionCoordinator ?? transitionCoordinator, image: image)
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated); appeared = true; hero.finishIfNotAnimating()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let sheet, sheet.isBeingDismissed || sheet.parent?.isBeingDismissed == true else { return }
            hero.closing(with: sheet.transitionCoordinator ?? transitionCoordinator, image: image)
        }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); hero.finishIfNotAnimating() }
    }
}
