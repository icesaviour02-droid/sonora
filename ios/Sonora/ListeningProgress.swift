import Foundation

/// Counts time actually heard, excluding pauses, buffering, seeks and restores from the queue.
struct ListeningProgress {
    private(set) var heard: Double = 0
    private(set) var startedAt: Date?
    private(set) var submitted = false
    private var position: Double?
    private var uptime: Double?
    private var wasPlaying = false

    mutating func sample(position: Double, uptime: Double, playing: Bool, now: Date = .now) {
        guard position.isFinite, uptime.isFinite else { rebase(); return }
        if playing && startedAt == nil { startedAt = now }
        if wasPlaying, let oldPosition = self.position, let oldUptime = self.uptime {
            let moved = position - oldPosition
            let wall = uptime - oldUptime
            // Seeks cannot earn a listen. The small tolerance covers independent native clock sampling.
            if moved >= 0, wall >= 0, moved <= wall + 0.2 { heard += min(moved, wall) }
        }
        self.position = position
        self.uptime = uptime
        wasPlaying = playing
    }

    mutating func rebase() { position = nil; uptime = nil; wasPlaying = false }

    /// Uses the desktop's thirty-second minimum and half-track/four-minute threshold.
    mutating func earn(duration: Double) -> Bool {
        guard !submitted, startedAt != nil, duration.isFinite, duration >= 30,
              heard >= min(240, duration / 2) else { return false }
        submitted = true
        return true
    }
}
