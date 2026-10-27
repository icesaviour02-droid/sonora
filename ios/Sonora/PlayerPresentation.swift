import SwiftUI
import UIKit

/// Uses UIKit's continuously interactive whole-screen zoom between Now Playing and its live accessory.
struct PlayerPresentation<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let hero: PlayerHeroState
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ presenter: Presenter, context: Context) {
        presenter.update(show: isPresented, root: AnyView(content().environment(\.self, context.environment)),
            hero: hero, changed: { isPresented = $0 })
    }

    final class Presenter: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var player: Hosting?
        private var changed: ((Bool) -> Void)?
        private var wanted = false
        private var root: AnyView = AnyView(EmptyView())
        private weak var hero: PlayerHeroState?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reconcile() }

        func update(show: Bool, root: AnyView, hero: PlayerHeroState, changed: @escaping (Bool) -> Void) {
            wanted = show; self.root = root; self.hero = hero; self.changed = changed
            player?.rootView = root
            reconcile()
        }
        private func reconcile() {
            if !wanted, let player, !player.isBeingDismissed {
                player.dismiss(animated: true) { [weak self, weak player] in
                    guard let self, let player else { return }; self.closed(player)
                }
                return
            }
            guard viewIfLoaded?.window != nil else { return }
            if wanted, player == nil, presentedViewController == nil {
                let host = Hosting(rootView: root)
                host.modalPresentationStyle = .fullScreen
                host.modalPresentationCapturesStatusBarAppearance = true
                host.view.backgroundColor = .clear
                host.view.accessibilityIdentifier = "player-fullscreen"
                let options = UIViewController.Transition.ZoomOptions()
                options.interactiveDismissShouldBegin = { [weak host] context in
                    guard let host, host.presentedViewController == nil else { return false }
                    return context.velocity.dy > 0 && context.velocity.dy > abs(context.velocity.dx) &&
                        !Self.blocksDismissal(at: context.location, in: host.view)
                }
                host.preferredTransition = .zoom(options: options) { [weak self] _ in self?.hero?.pillView }
                host.didClose = { [weak self, weak host] in
                    guard let self, let host else { return }
                    self.closed(host)
                }
                player = host
                record("present")
                present(host, animated: true) { [weak self] in self?.record("present-complete") }
                host.presentationController?.delegate = self
            }
        }

        private func closed(_ host: UIViewController) {
            guard player === host, host.presentingViewController == nil else { return }
            player = nil; wanted = false; changed?(false)
            record("native-dismiss-cleanup")
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            closed(presentationController.presentedViewController)
        }

        /// Native scrolling, sliders and explicit SwiftUI control rectangles keep their own gestures.
        private static func blocksDismissal(at point: CGPoint, in root: UIView) -> Bool {
            func excluded(_ view: UIView) -> Bool {
                if let zone = view as? PlayerDismissExclusion.Zone,
                   zone.window != nil, zone.convert(zone.bounds, to: root).contains(point) { return true }
                return view.subviews.contains(where: excluded)
            }
            if excluded(root) { return true }
            var hit = root.hitTest(point, with: nil)
            while let view = hit, view !== root {
                if view is UIControl || view is UIScrollView { return true }
                hit = view.superview
            }
            return false
        }

        /// DEBUG lifecycle evidence contains flags only, never account data or media content.
        private func record(_ event: String) {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--sonora-review-fullscreen") else { return }
            let url = URL.applicationSupportDirectory.appendingPathComponent("player-presentation-review.json")
            var events = ((try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [[String: Any]] ?? []
            events.append(["event": event, "wanted": wanted, "hasPlayer": player != nil,
                "hasPresented": presentedViewController != nil, "inWindow": viewIfLoaded?.window != nil])
            if let data = try? JSONSerialization.data(withJSONObject: Array(events.suffix(120))) {
                try? data.write(to: url, options: .atomic)
            }
            #endif
        }
    }

    /// Native lifecycle callbacks distinguish a completed dismissal from an interrupted pull.
    final class Hosting: UIHostingController<AnyView> {
        var didClose: (() -> Void)?
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentingViewController == nil else { return }
                self.didClose?()
            }
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
