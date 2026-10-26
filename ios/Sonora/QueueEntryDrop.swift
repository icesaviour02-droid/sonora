import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Queue drags carry an occurrence ID within this app, never a stream URL or provider token.
    static let sonoraQueueEntry = UTType(exportedAs: "org.sonorahq.iphone.queue-entry")
}

/// Rows move as the finger enters them; the system owns the drag preview and cancellation.
struct QueueEntryDrop: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let move: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragged != nil && info.hasItemsConforming(to: [.sonoraQueueEntry])
    }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        move(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
