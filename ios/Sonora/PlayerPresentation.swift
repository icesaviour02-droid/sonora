import SwiftUI
import UIKit

/// Keeps the player as one full-window surface while a downward drag controls its native transition.
struct PlayerPresentation<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let hero: PlayerHeroState
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ presenter: Presenter, context: Context) {
        let root = AnyView(content().environment(\.self, context.environment))
        presenter.update(show: isPresented, root: root, hero: hero, changed: { isPresented = $0 })
    }

    final class Presenter: UIViewController, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
        private var player: Hosting?
        private var changed: ((Bool) -> Void)?
        private var hero: PlayerHeroState?
        private var interaction: UIPercentDrivenInteractiveTransition?
        private var wanted = false
        private var dismissalSucceeded = false
        private var retryScheduled = false
        private var root: AnyView = AnyView(EmptyView())
        override func loadView() {
            let anchor = WindowAnchor()
            anchor.attached = { [weak self] in self?.reconcile() }
            anchor.isUserInteractionEnabled = false
            view = anchor
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reconcile() }

        /// Tab changes can attach a background presenter without another controller appearance callback.
        private final class WindowAnchor: UIView {
            var attached: (() -> Void)?
            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard window != nil else { return }
                // Complete hierarchy attachment before asking UIKit to present a controller.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window != nil else { return }
                    self.attached?()
                }
            }
        }

        func update(show: Bool, root: AnyView, hero: PlayerHeroState, changed: @escaping (Bool) -> Void) {
            wanted = show; self.root = root; self.hero = hero; self.changed = changed
            record("update")
            player?.rootView = root
            reconcile()
        }
        private func reconcile() {
            guard viewIfLoaded?.window != nil else { return }
            if wanted, player == nil, presentedViewController == nil {
                // SwiftUI can still be dismissing its error alert when the user opens a song.
                var owner: UIViewController? = self
                while let controller = owner {
                    if controller.presentedViewController != nil || controller.isBeingDismissed || controller.isBeingPresented {
                        record("waiting-for-presentation")
                        retryPresentation()
                        return
                    }
                    owner = controller.parent
                }
                let host = Hosting(rootView: root)
                host.modalPresentationStyle = .custom
                host.modalPresentationCapturesStatusBarAppearance = true
                host.transitioningDelegate = self
                host.view.backgroundColor = .clear
                host.view.accessibilityIdentifier = "player-fullscreen"
                let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
                pan.delegate = self; host.view.addGestureRecognizer(pan)
                player = host
                record("present")
                present(host, animated: true) { [weak self] in self?.record("present-complete") }
                // A rejected UIKit presentation never completes; retain the request rather than a stale host.
                DispatchQueue.main.async { [weak self, weak host] in
                    guard let self, let host, self.player === host, host.presentingViewController == nil else { return }
                    self.player = nil
                    self.retryPresentation()
                }
            } else if !wanted, let player, !player.isBeingDismissed {
                player.dismiss(animated: true) { [weak self] in self?.player = nil; self?.reconcile() }
            }
        }

        /// Coalesces retries while an ancestor alert or sheet finishes its native transition.
        private func retryPresentation() {
            guard wanted, !retryScheduled else { return }
            retryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.retryScheduled = false
                self.reconcile()
            }
        }

        /// DEBUG evidence records lifecycle flags only, without account or media content.
        private func record(_ event: String) {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let downloadReview = arguments.contains { $0.contains("sonora://downloadlyrics") }
            guard arguments.contains("--sonora-review-fullscreen") || downloadReview else { return }
            let filename = downloadReview ? "download-player-presentation-review.json" : "player-presentation-review.json"
            let url = URL.applicationSupportDirectory.appendingPathComponent(filename)
            var events = ((try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [[String: Any]] ?? []
            events.append(["event": event, "wanted": wanted, "hasPlayer": player != nil,
                "hasPresented": presentedViewController != nil, "inWindow": viewIfLoaded?.window != nil])
            if let data = try? JSONSerialization.data(withJSONObject: Array(events.suffix(120))) {
                try? data.write(to: url, options: .atomic)
            }
            #endif
        }

        /// Sliders/buttons keep their touches; queue/history scrolling keeps its native vertical gesture.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let player,
                  player.presentedViewController == nil, !player.isBeingPresented else { return false }
            let velocity = pan.velocity(in: player.view)
            guard velocity.y > 0, velocity.y > abs(velocity.x) else { return false }
            let point = pan.location(in: player.view)
            func blocked(_ view: UIView) -> Bool {
                if let zone = view as? PlayerDismissExclusion.Zone,
                   zone.window != nil, zone.convert(zone.bounds, to: player.view).contains(point) { return true }
                return view.subviews.contains(where: blocked)
            }
            if blocked(player.view) { return false }
            var hit = player.view.hitTest(point, with: nil)
            while let view = hit, view !== player.view {
                if view is UIControl || view is UIScrollView { return false }
                hit = view.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func drag(_ pan: UIPanGestureRecognizer) {
            guard let player else { return }
            let height = max(1, player.view.bounds.height)
            let progress = min(1, max(0, pan.translation(in: player.view).y / height))
            switch pan.state {
            case .began:
                let driver = UIPercentDrivenInteractiveTransition()
                driver.completionCurve = .easeOut
                interaction = driver
                dismissalSucceeded = false
                player.dismiss(animated: true) { [weak self] in
                    guard let self, self.dismissalSucceeded else { return }
                    self.player = nil; self.wanted = false; self.changed?(false)
                    self.record("interactive-cleanup")
                    self.reconcile()
                }
                driver.update(progress)
            case .changed: interaction?.update(progress)
            case .ended, .cancelled:
                let velocity = pan.velocity(in: player.view).y
                let projected = progress + velocity / height * 0.2
                let finish = pan.state != .cancelled && (progress > 0.25 || projected > 0.35) && velocity > -100
                let remaining = max(1, height * (1 - progress))
                let settle = min(Layout.playerDismissMaximumSettle,
                    max(Layout.playerDismissMinimumSettle, Double(remaining / max(1, velocity))))
                if finish {
                    // Keep a long pull from reducing the remaining cover journey to a few frames.
                    interaction?.completionSpeed = CGFloat(Layout.playerTransitionDuration / settle) * max(0.001, 1 - progress)
                } else {
                    interaction?.completionSpeed = min(1.5, max(0.5, abs(velocity) / height))
                }
                hero?.release(committing: finish, settleDuration: settle)
                if finish { interaction?.finish() } else { interaction?.cancel() }
                interaction = nil
            default: break
            }
        }

        func animationController(forPresented presented: UIViewController, presenting: UIViewController,
            source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { Animator(opening: true, hero: hero) }
        func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
            Animator(opening: false, hero: hero) { [weak self] success in
                guard let self else { return }
                self.dismissalSucceeded = success
                self.record(success ? "dismiss-animation-finished" : "dismiss-canceled")
            }
        }
        func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning)
            -> (any UIViewControllerInteractiveTransitioning)? { interaction }
        func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
            source: UIViewController) -> UIPresentationController? { Fullscreen(presentedViewController: presented, presenting: presenting) }
    }

    final class Hosting: UIHostingController<AnyView> {
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    }
    final class Fullscreen: UIPresentationController {
        override var shouldRemovePresentersView: Bool { false }
        override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }
        override func containerViewWillLayoutSubviews() {
            guard let containerView, let presentedView else { return }
            presentedView.bounds = CGRect(origin: .zero, size: containerView.bounds.size)
            presentedView.center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        }
    }

    /// Artwork, labels and controls remain inside this single interruptible moving surface, including cancellation.
    final class Animator: NSObject, UIViewControllerAnimatedTransitioning {
        let opening: Bool
        let hero: PlayerHeroState?
        private var animator: UIViewPropertyAnimator?
        let completed: (Bool) -> Void
        init(opening: Bool, hero: PlayerHeroState?, completed: @escaping (Bool) -> Void = { _ in }) {
            self.opening = opening; self.hero = hero; self.completed = completed
        }
        func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval { Layout.playerTransitionDuration }
        func animateTransition(using context: any UIViewControllerContextTransitioning) {
            interruptibleAnimator(using: context).startAnimation()
        }
        func interruptibleAnimator(using context: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
            if let animator { return animator }
            let container = context.containerView
            let key: UITransitionContextViewControllerKey = opening ? .to : .from
            let controller = context.viewController(forKey: key)!
            let surface = controller.view!
            if opening { container.addSubview(surface) }
            surface.frame = container.bounds
            surface.layoutIfNeeded()
            if opening { surface.setNeedsLayout(); surface.layoutIfNeeded() }
            let reduced = UIAccessibility.isReduceMotionEnabled
            hero?.begin(surface: surface, opening: opening, interactive: context.isInteractive)
            surface.layer.cornerCurve = .continuous
            surface.layer.masksToBounds = true
            surface.layer.cornerRadius = reduced ? 0 : Layout.playerDismissRadius
            if opening {
                if reduced { surface.alpha = 0 }
                else { surface.transform = CGAffineTransform(translationX: 0, y: container.bounds.height) }
            }
            let animation = UIViewPropertyAnimator(duration: transitionDuration(using: context), dampingRatio: 1) {
                if reduced { surface.alpha = self.opening ? 1 : 0 }
                else { surface.transform = self.opening ? .identity : CGAffineTransform(translationX: 0, y: container.bounds.height) }
                surface.layer.cornerRadius = self.opening || reduced ? 0 : Layout.playerDismissRadius
            }
            animation.addCompletion { _ in
                let success = !context.transitionWasCancelled
                surface.transform = .identity; surface.alpha = 1
                surface.layer.cornerRadius = 0; surface.layer.masksToBounds = false
                if !success && self.opening { surface.removeFromSuperview() }
                self.hero?.finish(completed: success)
                self.completed(success)
                context.completeTransition(success)
                self.animator = nil
            }
            animator = animation
            return animation
        }
    }
}

/// Marks control rectangles that must never be intercepted by the fullscreen dismiss gesture.
struct PlayerDismissExclusion: UIViewRepresentable {
    func makeUIView(context: Context) -> Zone { Zone() }
    func updateUIView(_ view: Zone, context: Context) {}
    final class Zone: UIView {
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
