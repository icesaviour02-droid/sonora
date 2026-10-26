import AVFoundation
import Foundation
import CoreMedia
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
    /// Imports a tagged, self-generated recording for native playlist presentation checks.
    func importReviewRecording() async -> MusicTrack? {
        let before = Set(tracks.map(\.id))
        do {
            let file = try await files.taggedReviewFile(URL.cachesDirectory.appendingPathComponent("sonora-review-tone.wav"))
            defer { try? FileManager.default.removeItem(at: file) }
            await importFiles([file])
            return tracks.first { !before.contains($0.id) }
        } catch { return nil }
    }

    /// The populated Downloads capture uses the same import and persistent transfer models.
    func reviewDownloads(_ downloads: DownloadsStore) {
        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self, let track = await self.importReviewRecording() else { return }
            await downloads.reviewDownloads(file: self.url(for: track), track: track)
        }
    }

    /// Imports the runner's generated WAV, checks the real player clock and removes that import.
    func reviewLocalPlayback(_ playback: PlaybackController) {
        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self else { return }
            let before = Set(self.tracks.map(\.id))
            let source = URL.cachesDirectory.appendingPathComponent("sonora-review-tone.wav")
            var checks: [String: Bool] = [:]
            let tagged: URL?
            do { tagged = try await self.files.taggedReviewFile(source) }
            catch { tagged = nil }
            defer { if let tagged { try? FileManager.default.removeItem(at: tagged) } }
            checks["tagged_fixture_exported"] = tagged != nil
            await self.importFiles([tagged ?? source])
            if let track = self.tracks.first(where: { !before.contains($0.id) }) {
                checks["imported_playable_file"] = FileManager.default.fileExists(atPath: self.url(for: track).path)
                checks["duration_imported"] = (track.durationSeconds ?? 0) > 10
                checks["embedded_metadata"] = track.title == "Sonora Review Tone" && track.artist == "Sonora Review Artist" && track.albumTitle == "Sonora Review Album"
                let cover = track.displayArtworkURL
                if let cover, let data = try? await ArtworkFiles.shared.data(cover) {
                    checks["embedded_cover"] = !data.isEmpty && cover.isFileURL
                } else { checks["embedded_cover"] = false }
                let reloaded = try? await LibraryFiles().load()
                checks["cover_metadata_restore"] = reloaded?.first { $0.id == track.id }?.displayArtworkURL == cover && cover != nil
                let lyrics = LyricsStore()
                lyrics.load(nil, title: track.title, artist: track.artist, sources: ["Local"], cacheID: track.id, savedOnly: true)
                for _ in 0..<150 {
                    if !lyrics.isLoading { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                checks["embedded_lyrics_saved"] = lyrics.sheet?.source == "Local" && lyrics.sheet?.lines?.count == 2
                let localAlbums = LocalAlbum.collect(self.tracks)
                checks["local_album_indexed"] = localAlbums.contains { $0.title == track.albumTitle && $0.tracks.contains { $0.id == track.id } }
                let first = MusicTrack(id: "review-1", title: "Second", artist: "Artist A", filename: "", addedAt: .now,
                    albumTitle: "Compilation", albumArtist: "Various Artists", trackNumber: 2, discNumber: 1)
                let second = MusicTrack(id: "review-2", title: "First", artist: "Artist B", filename: "", addedAt: .now,
                    albumTitle: "Compilation", albumArtist: "Various Artists", trackNumber: 1, discNumber: 1)
                let third = MusicTrack(id: "review-3", title: "Other", artist: "Other Artist", filename: "", addedAt: .now,
                    albumTitle: "Compilation", trackNumber: 1)
                let grouped = LocalAlbum.collect([first, second, third])
                checks["compilation_track_order"] = grouped.count == 2 && grouped.first { $0.artist == "Various Artists" }?.tracks.map(\.id) == [second.id, first.id]
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
                let timeline = await playback.reviewTimeline(track: track, url: self.url(for: track))
                checks.merge(timeline) { _, new in new }
                await self.remove(track)
                playback.reconcile(with: self.tracks)
                checks["remove_import"] = Set(self.tracks.map(\.id)) == before && !FileManager.default.fileExists(atPath: self.url(for: track).path)
                checks["cover_cleanup"] = cover.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
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
        var cover: String?
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
                    if item.commonKey == .commonKeyArtwork, let value = try? await item.load(.dataValue) {
                        cover = try? await ArtworkFiles.shared.save(value, id: id)
                    }
                }
            }
            var albumArtist: String?
            var trackNumber: Int?
            var discNumber: Int?
            var embeddedLyrics: String?
            if let metadata = try? await asset.load(.metadata) {
                for item in metadata {
                    guard let identifier = item.identifier else { continue }
                    if [.iTunesMetadataAlbumArtist, .id3MetadataBand].contains(identifier),
                       let value = try? await item.load(.stringValue), !value.isEmpty { albumArtist = value }
                    if [.iTunesMetadataTrackNumber, .id3MetadataTrackNumber].contains(identifier) {
                        trackNumber = await Self.number(item)
                    }
                    if [.iTunesMetadataDiscNumber, .id3MetadataPartOfASet].contains(identifier) {
                        discNumber = await Self.number(item)
                    }
                    if [.iTunesMetadataLyrics, .id3MetadataUnsynchronizedLyric].contains(identifier),
                       let value = try? await item.load(.stringValue) { embeddedLyrics = value }
                }
            }
            let seconds = (try? await asset.load(.duration))?.seconds
            let duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let track = MusicTrack(id: id.uuidString, title: title, artist: artist, filename: filename,
                addedAt: .now, albumTitle: album, durationSeconds: duration, artworkFilename: cover, albumArtist: albumArtist, trackNumber: trackNumber, discNumber: discNumber)
            var next = tracks
            next.append(track)
            if let embeddedLyrics { try? await LyricsStore.saveEmbedded(embeddedLyrics, trackID: track.id) }
            try save(next)
            tracks = next
            return track
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let cover { await ArtworkFiles.shared.remove(cover) }
            await LyricsStore.removeImported(trackID: id.uuidString)
            throw error
        }
    }

    func remove(_ track: MusicTrack) async throws {
        let next = tracks.filter { $0.id != track.id }
        // Persist first: a failed write must not leave the index pointing at a deleted file.
        try save(next)
        tracks = next
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(track.filename))
        if let cover = track.artworkFilename { await ArtworkFiles.shared.remove(cover) }
        await LyricsStore.removeImported(trackID: track.id)
    }

    /// ID3 spells "track/total" as text; iTunes stores the track in the third/fourth data bytes.
    private static func number(_ item: AVMetadataItem) async -> Int? {
        if let value = try? await item.load(.stringValue), let first = value.split(separator: "/").first,
           let number = Int(first), number > 0 { return number }
        if let value = try? await item.load(.numberValue), value.intValue > 0 { return value.intValue }
        if let data = try? await item.load(.dataValue), data.count >= 4 {
            let number = Int(data[data.startIndex + 2]) * 256 + Int(data[data.startIndex + 3])
            return number > 0 ? number : nil
        }
        return nil
    }

    #if DEBUG
    /// Writes a self-generated test recording with real container metadata through AVFoundation.
    func taggedReviewFile(_ source: URL) async throws -> URL {
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileWriteUnknown) }
        let output = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        var metadata: [AVMetadataItem] = []
        let fields: [(AVMetadataIdentifier, String)] = [
            (.commonIdentifierTitle, "Sonora Review Tone"), (.commonIdentifierArtist, "Sonora Review Artist"),
            (.commonIdentifierAlbumName, "Sonora Review Album"), (.iTunesMetadataAlbumArtist, "Sonora Review Artist"),
            (.iTunesMetadataLyrics, "[00:01]Sonora shines\n[00:04]Keep the music moving")]
        for (identifier, text) in fields {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = text as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            metadata.append(item)
        }
        let png = try Data(contentsOf: URL.cachesDirectory.appendingPathComponent("sonora-review-cover.png"))
        let cover = try await ArtworkFiles.shared.save(png, id: UUID())
        let coverURL = ArtworkFiles.root.appendingPathComponent(cover)
        let jpeg = try Data(contentsOf: coverURL)
        await ArtworkFiles.shared.remove(cover)
        let picture = AVMutableMetadataItem()
        picture.identifier = .commonIdentifierArtwork
        picture.value = jpeg as NSData
        picture.dataType = kCMMetadataBaseDataType_JPEG as String
        metadata.append(picture)
        exporter.metadata = metadata
        do { try await exporter.export(to: output, as: .m4a); return output }
        catch { try? FileManager.default.removeItem(at: output); throw error }
    }
    #endif

    private func save(_ value: [MusicTrack]) throws {
        try JSONEncoder().encode(value).write(to: index, options: .atomic)
    }
}
