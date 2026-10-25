import AVFoundation
import MediaPlayer
import Observation
import UIKit

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
    private(set) var streamBadge: String?
    private(set) var currentLoudnessDB: Float?
    var error: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let downloads: DownloadsStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemObserver: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var commands: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var originalQueue: [MusicTrack] = []
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var scrobbledTrackID: String?
    @ObservationIgnored private var interruptedWhilePlaying = false
    @ObservationIgnored private var didRestore = false
    private let snapshotKey = "sonora.ios.queue.v1"

    init(downloads: DownloadsStore, settings: SettingsStore) {
        self.downloads = downloads
        self.settings = settings
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                if let deadline = self.settings.sleepTimerDeadline, Date() >= deadline {
                    self.settings.setSleepTimer(.off)
                    self.pause()
                    return
                }
                if self.isPlaying, let current = self.current, self.scrobbledTrackID != current.id, self.elapsed >= 15 {
                    self.scrobbledTrackID = current.id
                    self.settings.submitScrobble(current)
                }
                #if DEBUG
                self.writeReviewState()
                #endif
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
        // Explicit playback wins over a still-pending library/queue restoration.
        didRestore = true
        error = nil
        let playable = tracks.filter { $0.available != false }
        originalQueue = playable.isEmpty ? [track] : playable
        queue = originalQueue
        isShuffled = false
        select(track, autoplay: true)
    }

    func playShuffled(_ tracks: [MusicTrack]) {
        let playable = tracks.filter { $0.available != false }
        guard let first = playable.randomElement() else { return }
        didRestore = true
        error = nil
        originalQueue = playable
        isShuffled = true
        queue = [first] + playable.filter { $0.id != first.id }.shuffled()
        select(first, autoplay: true)
    }

    func playNext(_ track: MusicTrack) {
        guard track.available != false else { return }
        if current == nil || queue.isEmpty {
            play(track, in: [track])
            return
        }
        queue.removeAll { $0.id == track.id && $0.id != current?.id }
        originalQueue.removeAll { $0.id == track.id && $0.id != current?.id }
        if let current, let index = queue.firstIndex(of: current) {
            queue.insert(track, at: min(index + 1, queue.count))
        } else {
            queue.insert(track, at: 0)
        }
        if let current, let index = originalQueue.firstIndex(of: current) {
            originalQueue.insert(track, at: min(index + 1, originalQueue.count))
        } else {
            originalQueue.append(track)
        }
        saveQueue()
    }

    func addToQueue(_ track: MusicTrack) {
        guard track.available != false else { return }
        if current == nil || queue.isEmpty {
            play(track, in: [track])
            return
        }
        if !queue.contains(where: { $0.id == track.id }) {
            queue.append(track)
        }
        if !originalQueue.contains(where: { $0.id == track.id }) {
            originalQueue.append(track)
        }
        saveQueue()
    }

    func addToQueue(_ tracks: [MusicTrack]) {
        let playable = tracks.filter { $0.available != false }
        guard !playable.isEmpty else { return }
        if current == nil || queue.isEmpty, let first = playable.first {
            play(first, in: playable)
            return
        }
        for track in playable {
            if !queue.contains(where: { $0.id == track.id }) { queue.append(track) }
            if !originalQueue.contains(where: { $0.id == track.id }) { originalQueue.append(track) }
        }
        saveQueue()
    }

    func moveQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        let count = queue.count
        var indices = Array(0..<count)
        let moving = source.map { indices[$0] }
        for index in source.sorted(by: >) {
            queue.remove(at: index)
        }
        let target = min(max(0, destination - source.filter { $0 < destination }.count), queue.count)
        let items = moving.compactMap { $0 < originalQueue.count ? originalQueue[$0] : nil }
        _ = items
        saveQueue()
        _ = target
    }

    func removeFromQueue(_ track: MusicTrack) {
        guard track.id != current?.id else { return }
        queue.removeAll { $0.id == track.id }
        originalQueue.removeAll { $0.id == track.id }
        saveQueue()
    }

    func clearUpcomingQueue() {
        guard let current else {
            queue = []
            originalQueue = []
            saveQueue()
            return
        }
        queue = [current]
        originalQueue = [current]
        saveQueue()
    }

    func startRadio(for track: MusicTrack) {
        guard let videoID = track.youtubeID else {
            play(track, in: [track])
            return
        }
        play(track, in: [track])
        Task { [weak self] in
            guard let self, let radioTracks = try? await NativeProvider.radio(videoID: videoID), !radioTracks.isEmpty else { return }
            var combined = [track]
            for item in radioTracks where item.id != track.id {
                combined.append(item)
            }
            self.originalQueue = combined
            self.queue = combined
            self.saveQueue()
        }
    }

    func select(_ track: MusicTrack, autoplay: Bool = true) {
        guard queue.contains(track) else { return }
        pause()
        var localItem: AVPlayerItem?
        currentLoudnessDB = nil
        if let downloaded = downloads.fileURL(for: track.id) {
            localItem = AVPlayerItem(url: downloaded)
            streamBadge = String(localized: "ios-downloaded")
        } else if track.youtubeID == nil {
            let url = URL.applicationSupportDirectory.appendingPathComponent("Audio").appendingPathComponent(track.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                error = String(localized: "ios-missing-file")
                return
            }
            localItem = AVPlayerItem(url: url)
            streamBadge = String(localized: "ios-local-audio")
        } else {
            streamBadge = nil
        }
        current = track
        scrobbledTrackID = nil
        elapsed = 0
        duration = track.durationSeconds ?? 0
        itemObserver = nil
        player.replaceCurrentItem(with: nil)
        applyAudioGain()
        if let localItem { install(localItem) }
        saveQueue()
        loadLockScreenArtwork(for: track)
        publishNowPlaying()
        if autoplay {
            settings.recordHistory(track)
            resume()
        }
    }

    func applyAudioGain() {
        var totalDB: Float = 0
        if settings.normalizeVolume, let loudness = currentLoudnessDB, loudness.isFinite {
            // YouTube loudness_db is relative to reference; negative values mean quieter than reference, positive louder.
            totalDB -= min(max(loudness, -12), 12)
        }
        if settings.equalizerEnabled {
            totalDB += Float(settings.preampDB)
            totalDB += Float(settings.bassDB * 0.2 + settings.trebleDB * 0.15)
        }
        let linear = pow(10.0, totalDB / 20.0)
        player.volume = min(max(linear, 0.1), 1.0)
    }

    private func install(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        applyAudioGain()
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
        settings.recordHistory(current)
        if player.currentItem == nil, let videoID = current.youtubeID {
            if let downloaded = downloads.fileURL(for: current.id) {
                streamBadge = String(localized: "ios-downloaded")
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
            applyAudioGain()
            player.play()
        } catch {
            self.error = String(localized: "ios-audio-session-error")
            publishNowPlaying()
        }
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
        let quality = settings.streamingQuality
        resolutionTask = Task { [weak self] in
            do {
                let stream = try await NativeProvider.resolve(videoID, quality: quality)
                try Task.checkCancellation()
                guard let self, self.current?.id == trackID else { return }
                self.currentLoudnessDB = stream.loudness_db
                let codec = (stream.codec ?? "AAC").uppercased()
                if let kbps = stream.bitrate_kbps, kbps > 0 {
                    self.streamBadge = "\(codec) · \(kbps) kbps"
                } else {
                    self.streamBadge = codec
                }
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
                self.publishNowPlaying()
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
        if automatically && settings.sleepTimer == .endOfTrack {
            settings.setSleepTimer(.off)
            pause()
            return
        }
        guard let current, let index = queue.firstIndex(of: current) else { return }
        if automatically && repeatMode == .one { seek(to: 0); resume(); return }
        if index + 1 < queue.count {
            select(queue[index + 1])
        } else if repeatMode == .all, let first = queue.first {
            select(first)
        } else if automatically, settings.autoplayRadio, let videoID = current.youtubeID {
            extendWithRadio(videoID: videoID, after: current)
        } else {
            pause()
        }
    }

    private func extendWithRadio(videoID: String, after currentTrack: MusicTrack) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let tracks = (try? await NativeProvider.radio(videoID: videoID)) ?? []
            let existing = Set(self.queue.map(\.id))
            let fresh = tracks.filter { !existing.contains($0.id) && $0.available != false }
            guard let first = fresh.first, self.current?.id == currentTrack.id else {
                self.isLoading = false
                self.pause()
                return
            }
            self.queue.append(contentsOf: fresh)
            self.originalQueue.append(contentsOf: fresh)
            self.saveQueue()
            self.select(first, autoplay: true)
        }
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

    /// Drops account-backed queue data when the active provider identity changes.
    func clearRemoteQueue() {
        if current?.youtubeID != nil {
            pause()
            player.replaceCurrentItem(with: nil)
            current = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        queue.removeAll { $0.youtubeID != nil }
        originalQueue.removeAll { $0.youtubeID != nil }
        saveQueue()
    }

    private func loadLockScreenArtwork(for track: MusicTrack) {
        artworkTask?.cancel()
        if artworkTrackID != track.id {
            nowPlayingArtwork = nil
            artworkTrackID = track.id
        }
        guard let url = track.artworkURL else { return }
        let trackID = track.id
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, self.current?.id == trackID else { return }
            self.nowPlayingArtwork = artwork
            self.publishNowPlaying()
        }
    }

    private func publishNowPlaying() {
        #if DEBUG
        writeReviewState()
        #endif
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let album = current.albumTitle, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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

    #if DEBUG
    /// Records playback advancement for the CLI simulator review, without stream URLs or audio.
    private func writeReviewState() {
        guard ProcessInfo.processInfo.arguments.contains("--sonora-review-url"), let current else { return }
        struct Review: Encodable {
            let trackID: String
            let elapsed: Double
            let isPlaying: Bool
            let isDownloaded: Bool
            let hasError: Bool
            let error: String?
        }
        let state = Review(trackID: current.id, elapsed: elapsed, isPlaying: isPlaying,
                           isDownloaded: downloads.fileURL(for: current.id) != nil, hasError: error != nil, error: error)
        let url = URL.applicationSupportDirectory.appendingPathComponent("playback-review.json")
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
    }
    #endif

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
