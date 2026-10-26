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
        let allowed = dragged != nil && info.hasItemsConforming(to: [.sonoraQueueEntry])
        #if DEBUG
        QueueDragDiagnostics.record("validate:\(allowed)")
        #endif
        return allowed
    }

    func dropEntered(info: DropInfo) {
        #if DEBUG
        QueueDragDiagnostics.record("enter:" + target.uuidString)
        #endif
        guard let dragged, dragged != target else { return }
        move(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        #if DEBUG
        QueueDragDiagnostics.record("drop:" + target.uuidString)
        #endif
        dragged = nil
        return true
    }
}

#if DEBUG
/// Small simulator-only event evidence distinguishes a failed drag from a failed accessibility query.
enum QueueDragDiagnostics {
    private static let lock = NSLock()
    private static var url: URL { URL.applicationSupportDirectory.appendingPathComponent("queue-drag-review.json") }

    static func reset() { try? JSONEncoder().encode([String]()).write(to: url, options: .atomic) }

    static func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        var events = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
        guard events.count < 32, events.last != message else { return }
        events.append(message)
        try? JSONEncoder().encode(events).write(to: url, options: .atomic)
    }
}
#endif
