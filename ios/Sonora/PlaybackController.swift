import AVFoundation
import MediaPlayer
import Observation

/// Owns the player and queue for the app lifetime; views only send playback actions.
@MainActor @Observable
final class PlaybackController {
    private(set) var queue: [MusicTrack] = []
    private(set) var current: MusicTrack?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    var error: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let downloads: DownloadsStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemObserver: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var commands: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var originalQueue: [MusicTrack] = []
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var interruptedWhilePlaying = false
    @ObservationIgnored private var didRestore = false
    private let snapshotKey = "sonora.ios.queue.v1"

    init(downloads: DownloadsStore) {
        self.downloads = downloads
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                let duration = seconds.isFinite ? max(0, seconds) : (self.current?.durationSeconds ?? 0)
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
                if self.resolutionTask == nil {
                    self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                }
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
    func restore(from tracks: [MusicTrack]) {
        guard !didRestore else { return }
        didRestore = true
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        queue = (snapshot.tracks ?? snapshot.ids.compactMap { byID[$0] }).filter {
            $0.youtubeID != nil || byID[$0.id] != nil
        }
        originalQueue = queue
        if let id = snapshot.current, let track = queue.first(where: { $0.id == id }) {
            select(track, autoplay: false)
        }
    }

    /// Initialization and later library updates share one path, independent of SwiftUI callback order.
    func synchronizeLibrary(with tracks: [MusicTrack]) {
        if didRestore { reconcile(with: tracks) }
        else { restore(from: tracks) }
    }

    func play(_ track: MusicTrack, in tracks: [MusicTrack]) {
        guard track.available != false else { return }
        originalQueue = tracks
        queue = tracks.filter { $0.available != false }
        isShuffled = false
        select(track, autoplay: true)
    }

    func select(_ track: MusicTrack, autoplay: Bool = true) {
        guard queue.contains(track) else { return }
        pause()
        var localItem: AVPlayerItem?
        if let downloaded = downloads.fileURL(for: track.id) {
            localItem = AVPlayerItem(url: downloaded)
        } else if track.youtubeID == nil {
            let url = URL.applicationSupportDirectory.appendingPathComponent("Audio").appendingPathComponent(track.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                error = String(localized: "ios-missing-file")
                return
            }
            localItem = AVPlayerItem(url: url)
        }
        current = track
        elapsed = 0
        duration = track.durationSeconds ?? 0
        itemObserver = nil
        player.replaceCurrentItem(with: nil)
        if let localItem { install(localItem) }
        saveQueue()
        publishNowPlaying()
        if autoplay { resume() }
    }

    private func install(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.error = String(localized: "ios-playback-error")
                self.pause()
            }
        }
    }

    func toggle() { (isPlaying || isLoading) ? pause() : resume() }

    func resume() {
        guard let current else { return }
        if player.currentItem == nil, let videoID = current.youtubeID {
            if let downloaded = downloads.fileURL(for: current.id) {
                install(AVPlayerItem(url: downloaded))
                startAudio()
                return
            }
            resolve(videoID, for: current.id)
            return
        }
        startAudio()
    }

    private func startAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
            if duration > 0 && elapsed >= duration { seek(to: 0) }
            player.play()
        } catch { self.error = String(localized: "ios-audio-session-error") }
    }

    func pause() {
        resolutionTask?.cancel()
        resolutionTask = nil
        player.pause()
        isPlaying = false
        isLoading = false
        publishNowPlaying()
    }

    /// Resolve just before playback. URLs are short-lived and may be bound to the device's network.
    private func resolve(_ videoID: String, for trackID: String) {
        resolutionTask?.cancel()
        isLoading = true
        resolutionTask = Task { [weak self] in
            do {
                let stream = try await NativeProvider.resolve(videoID)
                try Task.checkCancellation()
                guard let self, self.current?.id == trackID else { return }
                let asset = AVURLAsset(url: stream.url, options: [AVURLAssetHTTPUserAgentKey: stream.user_agent])
                self.install(AVPlayerItem(asset: asset))
                self.duration = stream.duration_seconds ?? self.duration
                self.resolutionTask = nil
                self.isLoading = false
                self.startAudio()
            } catch is CancellationError {
                // Pause or selecting another track already reset this request's state.
            } catch {
                guard let self, self.current?.id == trackID else { return }
                self.resolutionTask = nil
                self.isLoading = false
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
            }
        }
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
    func reconcile(with tracks: [MusicTrack]) {
        let ids = Set(tracks.map(\.id))
        queue.removeAll { $0.youtubeID == nil && !ids.contains($0.id) }
        originalQueue.removeAll { $0.youtubeID == nil && !ids.contains($0.id) }
        if let current, current.youtubeID == nil, !ids.contains(current.id) {
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
        let ids: [String]
        let current: String?
        var tracks: [MusicTrack]? = nil
    }

    private func saveQueue() {
        let value = Snapshot(ids: queue.map(\.id), current: current?.id, tracks: queue)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: snapshotKey) }
    }
}
