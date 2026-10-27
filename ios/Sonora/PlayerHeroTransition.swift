import Observation
import SwiftUI
import UIKit

/// Resolves the currently visible accessory after native tab minimization or navigation changes.
@MainActor @Observable final class PlayerHeroState {
    @ObservationIgnored private(set) weak var pillView: UIView?
    func register(_ view: UIView) { pillView = view }
}

/// A full-accessory anchor supplies geometry to UIKit without a detached artwork snapshot.
struct PlayerHeroAnchor: UIViewRepresentable {
    let hero: PlayerHeroState
    func makeUIView(context: Context) -> Anchor { Anchor(hero: hero) }
    func updateUIView(_ view: Anchor, context: Context) { view.report() }

    final class Anchor: UIView {
        weak var hero: PlayerHeroState?
        init(hero: PlayerHeroState) {
            self.hero = hero
            super.init(frame: .zero); isUserInteractionEnabled = false; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() { guard window != nil, bounds.width > 0 else { return }; hero?.register(self) }
    }
}
