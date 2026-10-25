import AVFoundation
import MediaPlayer
import Observation

/// Owns the player and queue for the app lifetime; views only send playback actions.
@MainActor @Observable
final class PlaybackController {
    private(set) var queue: [LocalTrack] = []
    private(set) var current: LocalTrack?
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    var error: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemObserver: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var commands: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var originalQueue: [LocalTrack] = []
    @ObservationIgnored private var interruptedWhilePlaying = false
    @ObservationIgnored private var didRestore = false
    private let snapshotKey = "sonora.ios.queue.v1"

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                let duration = seconds.isFinite ? max(0, seconds) : 0
                if self.duration != duration {
                    self.duration = duration
                    self.publishNowPlaying()
                }
            }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.publishNowPlaying()
            }
        }
        observeNotifications()
        configureCommands()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notifications.forEach(NotificationCenter.default.removeObserver)
        commands.forEach { $0.0.removeTarget($0.1) }
    }

    /// Restores queue metadata only; launching the app never starts audio.
    func restore(from tracks: [LocalTrack]) {
        guard !didRestore else { return }
        didRestore = true
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        queue = snapshot.ids.compactMap { byID[$0] }
        originalQueue = queue
        if let id = snapshot.current, let track = byID[id], queue.contains(track) {
            select(track, autoplay: false)
        }
    }

    /// Initialization and later library updates share one path, independent of SwiftUI callback order.
    func synchronizeLibrary(with tracks: [LocalTrack]) {
        if didRestore { reconcile(with: tracks) }
        else { restore(from: tracks) }
    }

    func play(_ track: LocalTrack, in tracks: [LocalTrack]) {
        originalQueue = tracks
        queue = tracks
        isShuffled = false
        select(track, autoplay: true)
    }

    func select(_ track: LocalTrack, autoplay: Bool = true) {
        guard queue.contains(track) else { return }
        let url = URL.applicationSupportDirectory.appendingPathComponent("Audio").appendingPathComponent(track.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = String(localized: "ios-missing-file")
            return
        }
        current = track
        elapsed = 0
        duration = 0
        itemObserver = nil
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.error = String(localized: "ios-playback-error")
                self?.pause()
            }
        }
        saveQueue()
        publishNowPlaying()
        if autoplay { resume() }
    }

    func toggle() { isPlaying ? pause() : resume() }

    func resume() {
        guard current != nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
            if duration > 0 && elapsed >= duration { seek(to: 0) }
            player.play()
        } catch { self.error = String(localized: "ios-audio-session-error") }
    }

    func pause() {
        player.pause()
        isPlaying = false
        publishNowPlaying()
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        publishNowPlaying()
    }

    func next(automatically: Bool = false) {
        guard let current, let index = queue.firstIndex(of: current) else { return }
        if automatically && repeatMode == .one { seek(to: 0); resume(); return }
        if index + 1 < queue.count {
            select(queue[index + 1])
        } else if repeatMode == .all, let first = queue.first {
            select(first)
        } else { pause() }
    }

    func previous() {
        guard let current, let index = queue.firstIndex(of: current) else { return }
        if elapsed > 3 || index == 0 { seek(to: 0) }
        else { select(queue[index - 1]) }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled, let current {
            queue = [current] + originalQueue.filter { $0.id != current.id }.shuffled()
        } else { queue = originalQueue }
        saveQueue()
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    /// Removes deleted library entries from both queue orders and stops a deleted current item.
    func reconcile(with tracks: [LocalTrack]) {
        let ids = Set(tracks.map(\.id))
        queue.removeAll { !ids.contains($0.id) }
        originalQueue.removeAll { !ids.contains($0.id) }
        if let current, !ids.contains(current.id) {
            pause()
            player.replaceCurrentItem(with: nil)
            self.current = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        saveQueue()
    }

    private func publishNowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next(automatically: true)
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interruptedWhilePlaying = self.isPlaying
                    self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    if self.interruptedWhilePlaying && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        self.resume()
                    }
                    self.interruptedWhilePlaying = false
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.resume() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, target))
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackController) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
            return .success
        }
        commands.append((command, target))
    }

    private struct Snapshot: Codable {
        let ids: [UUID]
        let current: UUID?
    }

    private func saveQueue() {
        let value = Snapshot(ids: queue.map(\.id), current: current?.id)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: snapshotKey) }
    }
}
