import SwiftUI
import UIKit

/// Presents the player over the entire window and drives dismissal directly from a downward drag.
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
        private var root: AnyView = AnyView(EmptyView())
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reconcile() }

        func update(show: Bool, root: AnyView, hero: PlayerHeroState, changed: @escaping (Bool) -> Void) {
            wanted = show; self.root = root; self.hero = hero; self.changed = changed
            player?.rootView = root
            reconcile()
        }
        private func reconcile() {
            guard viewIfLoaded?.window != nil else { return }
            if wanted, player == nil, presentedViewController == nil {
                let host = Hosting(rootView: root)
                host.modalPresentationStyle = .custom
                host.transitioningDelegate = self
                host.view.backgroundColor = .clear
                host.view.accessibilityIdentifier = "player-fullscreen"
                let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
                pan.delegate = self; host.view.addGestureRecognizer(pan)
                player = host
                present(host, animated: true)
            } else if !wanted, let player, !player.isBeingDismissed {
                player.dismiss(animated: true) { [weak self] in self?.player = nil; self?.reconcile() }
            }
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
                player.dismiss(animated: true)
                driver.update(progress)
            case .changed: interaction?.update(progress)
            case .ended, .cancelled:
                let velocity = pan.velocity(in: player.view).y
                let projected = progress + velocity / height * 0.2
                let finish = pan.state != .cancelled && (progress > 0.25 || projected > 0.35) && velocity > -100
                interaction?.completionSpeed = min(1.5, max(0.5, abs(velocity) / height))
                if finish { interaction?.finish() } else { interaction?.cancel() }
                interaction = nil
            default: break
            }
        }

        func animationController(forPresented presented: UIViewController, presenting: UIViewController,
            source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { Animator(opening: true, hero: hero) }
        func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
            Animator(opening: false, hero: hero) { [weak self] success in
                guard success, let self else { return }
                self.player = nil; self.wanted = false; self.changed?(false)
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

    /// One interruptible UIKit animator drives the panel and shared cover, including a canceled pull.
    final class Animator: NSObject, UIViewControllerAnimatedTransitioning {
        let opening: Bool
        let hero: PlayerHeroState?
        private var animator: UIViewPropertyAnimator?
        let completed: (Bool) -> Void
        init(opening: Bool, hero: PlayerHeroState?, completed: @escaping (Bool) -> Void = { _ in }) {
            self.opening = opening; self.hero = hero; self.completed = completed
        }
        func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.5 }
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
            let flight = hero?.beginFlight(opening: opening, in: container)
            let reduced = UIAccessibility.isReduceMotionEnabled
            if opening {
                if reduced { surface.alpha = 0 }
                else { surface.transform = CGAffineTransform(translationX: 0, y: container.bounds.height) }
            }
            let animation = UIViewPropertyAnimator(duration: transitionDuration(using: context), dampingRatio: 1) {
                if reduced { surface.alpha = self.opening ? 1 : 0 }
                else { surface.transform = self.opening ? .identity : CGAffineTransform(translationX: 0, y: container.bounds.height) }
                flight?()
            }
            animation.addCompletion { [weak self] _ in
                let success = !context.transitionWasCancelled
                surface.transform = .identity; surface.alpha = 1
                if !success && self?.opening == true { surface.removeFromSuperview() }
                self?.hero?.finish()
                context.completeTransition(success)
                self?.completed(success)
                self?.animator = nil
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
