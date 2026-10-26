import AVFoundation
import Foundation
import Observation

/// Owns the durable local library. File IO and metadata work run on a separate actor.
@MainActor @Observable
final class LibraryStore {
    private(set) var tracks: [MusicTrack] = []
    private(set) var isImporting = false
    private(set) var isLoaded = false
    var error: String?
    private let files = LibraryFiles()
    #if DEBUG
    @ObservationIgnored private var reviewTask: Task<Void, Never>?
    #endif

    func load() async {
        guard !isLoaded else { return }
        do {
            tracks = try await files.load()
            isLoaded = true
        } catch {
            self.error = String(localized: "ios-library-load-error")
        }
    }

    /// Copies security-scoped selections before their temporary access expires.
    func importFiles(_ urls: [URL]) async {
        guard !isImporting, isLoaded else { return }
        isImporting = true
        defer { isImporting = false }
        var failures = false
        for url in urls {
            do {
                let track = try await files.importFile(url)
                tracks.append(track)
            } catch { failures = true }
        }
        if failures { error = String(localized: "ios-import-error") }
    }

    func remove(_ track: MusicTrack) async {
        do {
            try await files.remove(track)
            tracks.removeAll { $0.id == track.id }
        } catch { self.error = String(localized: "ios-delete-error") }
    }

    func url(for track: MusicTrack) -> URL {
        LibraryFiles.root.appendingPathComponent(track.filename)
    }

    #if DEBUG
    /// Imports the runner's generated WAV, checks the real player clock and removes that import.
    func reviewLocalPlayback(_ playback: PlaybackController) {
        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self else { return }
            let before = Set(self.tracks.map(\.id))
            let source = URL.cachesDirectory.appendingPathComponent("sonora-review-tone.wav")
            await self.importFiles([source])
            var checks: [String: Bool] = [:]
            if let track = self.tracks.first(where: { !before.contains($0.id) }) {
                checks["imported_playable_file"] = FileManager.default.fileExists(atPath: self.url(for: track).path)
                checks["duration_imported"] = (track.durationSeconds ?? 0) > 10
                playback.play(track, in: [track])
                checks["clock_advanced"] = await self.waitForClock(playback, beyond: 1)
                checks["native_audio_tap_processed"] = playback.audioEffects.processedFrames > 0
                playback.pause()
                try? await Task.sleep(for: .milliseconds(350))
                let paused = playback.elapsed
                try? await Task.sleep(for: .milliseconds(700))
                checks["pause_stable"] = !playback.isPlaying && abs(playback.elapsed - paused) < 0.2
                playback.seek(to: 5)
                playback.resume()
                checks["seek_resume"] = await self.waitForClock(playback, beyond: 6)
                playback.pause()
                await self.remove(track)
                playback.reconcile(with: self.tracks)
                checks["remove_import"] = Set(self.tracks.map(\.id)) == before && !FileManager.default.fileExists(atPath: self.url(for: track).path)
            } else { checks["imported_playable_file"] = false }
            let result: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks, "fixture": "generated WAV test tone"]
            if let data = try? JSONSerialization.data(withJSONObject: result) {
                try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("local-playback-review.json"), options: .atomic)
            }
        }
    }

    private func waitForClock(_ playback: PlaybackController, beyond threshold: Double) async -> Bool {
        for _ in 0..<150 {
            if Task.isCancelled { return false }
            if playback.error != nil { return false }
            if playback.isPlaying && playback.elapsed > threshold { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
    #endif
}

/// Serializes index mutations and keeps slow file/metadata work off the UI thread.
private actor LibraryFiles {
    static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Audio", isDirectory: true)
    }

    private var index: URL { Self.root.appendingPathComponent("library.json") }
    private var tracks: [MusicTrack] = []

    func load() throws -> [MusicTrack] {
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        // A damaged index is reported, never silently replaced with an empty library.
        tracks = try JSONDecoder().decode([MusicTrack].self, from: Data(contentsOf: index))
        return tracks
    }

    func importFile(_ source: URL) async throws -> MusicTrack {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let filename = id.uuidString + "." + source.pathExtension
        let destination = Self.root.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let asset = AVURLAsset(url: destination)
            guard try await asset.load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
            var title = source.deletingPathExtension().lastPathComponent
            var artist = String(localized: "ios-unknown-artist")
            var album: String?
            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata {
                    if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue) {
                        title = value
                    }
                    if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) {
                        artist = value
                    }
                    if item.commonKey == .commonKeyAlbumName, let value = try? await item.load(.stringValue) {
                        album = value
                    }
                }
            }
            let seconds = (try? await asset.load(.duration))?.seconds
            let duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let track = MusicTrack(id: id.uuidString, title: title, artist: artist, filename: filename,
                addedAt: .now, albumTitle: album, durationSeconds: duration)
            var next = tracks
            next.append(track)
            try save(next)
            tracks = next
            return track
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func remove(_ track: MusicTrack) throws {
        let next = tracks.filter { $0.id != track.id }
        // Persist first: a failed write must not leave the index pointing at a deleted file.
        try save(next)
        tracks = next
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(track.filename))
    }

    private func save(_ value: [MusicTrack]) throws {
        try JSONEncoder().encode(value).write(to: index, options: .atomic)
    }
}
