import AVFoundation
import Foundation
import Observation
import UIKit

/// A persisted transfer, keyed by the provider track, with a sandbox-owned destination.
struct DownloadEntry: Codable, Identifiable {
    enum State: String, Codable { case queued, resolving, downloading, downloaded, failed }
    var id: String { track.id }
    let track: MusicTrack
    var filename: String
    var state: State
    var taskID: Int?
    var expectedBytes: UInt64?
    var progress: Double = 0
    var failureCode: String? = nil
}

/// Delays the OS completion handler until all downloaded files and their metadata are finalized.
/// Delegate callbacks and UIKit can arrive on different queues, so this bookkeeping is locked.
private final class DownloadEvents: @unchecked Sendable {
    static let shared = DownloadEvents()
    private let lock = NSLock()
    private var pending = 0
    private var finished = false
    private var handler: (() -> Void)?

    func begin() { lock.lock(); pending += 1; lock.unlock() }
    func end() { lock.lock(); pending -= 1; lock.unlock(); deliverIfReady() }
    func finish() { lock.lock(); finished = true; lock.unlock(); deliverIfReady() }
    func receive(_ handler: @escaping () -> Void) {
        lock.lock(); self.handler = handler; lock.unlock(); deliverIfReady()
    }

    private func deliverIfReady() {
        lock.lock()
        let callback = finished && pending == 0 ? handler : nil
        if callback != nil { handler = nil; finished = false }
        lock.unlock()
        if let callback { DispatchQueue.main.async(execute: callback) }
    }
}

/// Reconnects background transfers when iOS relaunches the app after a transfer finishes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadsStore.sessionIdentifier else { completionHandler(); return }
        DownloadEvents.shared.receive(completionHandler)
    }
}

/// Owns the persistent download queue. URLSession, rather than a view or Rust worker, transfers
/// the bytes while iOS suspends the app. Two provider resolutions run together; the OS owns
/// transfer scheduling after requests are handed off.
@MainActor @Observable
final class DownloadsStore: NSObject, URLSessionDownloadDelegate {
    nonisolated static let sessionIdentifier = "org.sonorahq.iphone.downloads.v1"
    nonisolated static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    private(set) var entries: [DownloadEntry] = []
    private(set) var isRestoring = true
    var error: String?
    var allowsCellular: Bool {
        didSet { UserDefaults.standard.set(allowsCellular, forKey: "sonora.downloads.cellular") }
    }
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var resolving: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var transfers: [Int: URLSessionTask] = [:]
    @ObservationIgnored private var restoration: Task<Void, Never>?
    @ObservationIgnored private var lastProgress: [Int: Date] = [:]
    private var indexURL: URL { Self.root.appendingPathComponent("downloads.json") }

    var totalBytesUsed: UInt64 {
        entries.reduce(0) { sum, entry in
            guard entry.state == .downloaded else { return sum }
            if let expected = entry.expectedBytes { return sum + expected }
            let url = Self.root.appendingPathComponent(entry.filename)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + UInt64(max(0, bytes))
        }
    }

    override init() {
        allowsCellular = UserDefaults.standard.bool(forKey: "sonora.downloads.cellular")
        super.init()
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                entries = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: indexURL))
                guard entries.allSatisfy({ UUID(uuidString: ($0.filename as NSString).deletingPathExtension) != nil && ($0.filename as NSString).pathExtension == "m4a" }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        } catch { self.error = String(localized: "ios-download-restore-error") }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        restoration = Task { [weak self] in
            guard let self else { return }
            let tasks = await self.session.allTasks
            guard self.error == nil else { self.isRestoring = false; return }
            let active = Set(tasks.map(\.taskIdentifier))
            for index in self.entries.indices {
                switch self.entries[index].state {
                case .downloaded:
                    let url = Self.root.appendingPathComponent(self.entries[index].filename)
                    if !FileManager.default.fileExists(atPath: url.path) { self.entries[index].state = .failed }
                case .resolving, .queued:
                    self.entries[index].state = .queued
                case .downloading:
                    if !active.contains(self.entries[index].taskID ?? -1) { self.entries[index].state = .queued }
                case .failed: break
                }
            }
            let owned = Set(self.entries.compactMap(\.taskID))
            self.transfers = Dictionary(uniqueKeysWithValues: tasks.filter { owned.contains($0.taskIdentifier) }.map { ($0.taskIdentifier, $0) })
            tasks.filter { !owned.contains($0.taskIdentifier) }.forEach { $0.cancel() }
            self.isRestoring = false
            self.persist()
            self.pump()
        }
    }

    func entry(for id: String) -> DownloadEntry? { entries.first { $0.id == id } }

    /// Only completed, still-present files are offered to the playback controller.
    func fileURL(for id: String) -> URL? {
        guard let entry = entry(for: id), entry.state == .downloaded else { return nil }
        let url = Self.root.appendingPathComponent(entry.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func enqueue(_ track: MusicTrack) {
        guard error == nil, track.youtubeID != nil, track.available != false else { return }
        if let existing = entry(for: track.id) {
            if existing.state == .failed { retry(track.id) }
            return
        }
        entries.append(DownloadEntry(track: track, filename: UUID().uuidString + ".m4a", state: .queued))
        persist()
        pump()
    }

    func enqueueAll(_ tracks: [MusicTrack]) {
        guard error == nil else { return }
        var changed = false
        for track in tracks where track.youtubeID != nil && track.available != false {
            if let existing = entry(for: track.id) {
                if existing.state == .failed { retry(track.id) }
                continue
            }
            entries.append(DownloadEntry(track: track, filename: UUID().uuidString + ".m4a", state: .queued))
            changed = true
        }
        if changed {
            persist()
            pump()
        }
    }

    func retry(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].state == .failed else { return }
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(entries[index].filename))
        entries[index].filename = UUID().uuidString + ".m4a"
        entries[index].state = .queued
        entries[index].progress = 0
        entries[index].taskID = nil
        entries[index].expectedBytes = nil
        entries[index].failureCode = nil
        persist()
        pump()
    }

    func resumeQueue() { pump() }

    /// Cancels unfinished transfers and removes a completed download only when the listener asks.
    func remove(_ id: String) {
        guard let entry = entry(for: id) else { return }
        resolving.removeValue(forKey: id)?.cancel()
        entries.removeAll { $0.id == id }
        persist()
        if let taskID = entry.taskID {
            lastProgress.removeValue(forKey: taskID)
            transfers.removeValue(forKey: taskID)?.cancel()
        }
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(entry.filename))
        pump()
    }

    /// Isolates saved provider data when an account signs in or out, or when the listener clears all downloads.
    func clearRemoteDownloads() {
        let ids = entries.filter { $0.track.youtubeID != nil }.map(\.id)
        ids.forEach { remove($0) }
    }

    private func pump() {
        guard !isRestoring, error == nil, UIApplication.shared.applicationState != .background else { return }
        let active = entries.filter { $0.state == .resolving }.count
        let queued = entries.filter { $0.state == .queued }.prefix(max(0, 2 - active))
        for entry in queued { start(entry) }
    }

    private func start(_ entry: DownloadEntry) {
        guard let videoID = entry.track.youtubeID,
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].state = .resolving
        guard persist() else { entries[index].state = .queued; return }
        let qualityRaw = UserDefaults.standard.string(forKey: "sonora.settings.downloadQuality") ?? AudioQuality.high.rawValue
        let quality = AudioQuality(rawValue: qualityRaw) ?? .high
        resolving[entry.id] = Task { [weak self] in
            do {
                let stream = try await NativeProvider.resolve(videoID, quality: quality)
                try Task.checkCancellation()
                guard let length = stream.content_length, length > 0 else { throw ProviderError.unavailable }
                guard let self, let index = self.entries.firstIndex(where: { $0.filename == entry.filename }) else { return }
                var request = URLRequest(url: stream.url)
                request.setValue(stream.user_agent, forHTTPHeaderField: "User-Agent")
                request.setValue("bytes=0-\(length - 1)", forHTTPHeaderField: "Range")
                request.allowsCellularAccess = self.allowsCellular
                let transfer = self.session.downloadTask(with: request)
                transfer.taskDescription = entry.filename
                self.entries[index].taskID = transfer.taskIdentifier
                self.transfers[transfer.taskIdentifier] = transfer
                self.entries[index].expectedBytes = length
                self.entries[index].state = .downloading
                self.resolving.removeValue(forKey: entry.id)
                guard self.persist() else {
                    self.transfers.removeValue(forKey: transfer.taskIdentifier)
                    transfer.cancel()
                    return
                }
                transfer.resume()
                self.pump()
            } catch is CancellationError {
                // Removing a queued download owns the cancellation state.
            } catch {
                guard let self else { return }
                self.resolving.removeValue(forKey: entry.id)
                if let index = self.entries.firstIndex(where: { $0.filename == entry.filename }) {
                    self.entries[index].state = .failed
                    self.entries[index].failureCode = "resolve_failed"
                    self.persist()
                    self.pump()
                }
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
            error = nil
            return true
        }
        catch { self.error = String(localized: "ios-download-save-error"); return false }
    }

    private func failed(_ taskID: Int, reason: String = "transfer_failed") {
        guard let index = entries.firstIndex(where: { $0.taskID == taskID }) else { return }
        entries[index].state = .failed
        entries[index].taskID = nil
        entries[index].failureCode = reason
        lastProgress.removeValue(forKey: taskID)
        transfers.removeValue(forKey: taskID)
        persist()
        pump()
    }

    private func finalize(_ taskID: Int, url: URL?, failure: String?) async {
        defer { DownloadEvents.shared.end() }
        guard let index = entries.firstIndex(where: { $0.taskID == taskID }), let url else {
            if let url { try? FileManager.default.removeItem(at: url) }
            failed(taskID, reason: failure ?? "transfer_failed")
            return
        }
        let filename = entries[index].filename
        do {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if let expected = entries[index].expectedBytes, UInt64(bytes) != expected {
                try? FileManager.default.removeItem(at: url)
                failed(taskID, reason: "size_mismatch")
                return
            }
            guard try await AVURLAsset(url: url).load(.isPlayable) else {
                try? FileManager.default.removeItem(at: url)
                failed(taskID, reason: "unplayable")
                return
            }
            // Awaiting metadata can race removal. Never resurrect a transfer the listener removed.
            guard let current = entries.firstIndex(where: { $0.filename == filename }) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            entries[current].state = .downloaded
            entries[current].progress = 1
            entries[current].taskID = nil
            entries[current].failureCode = nil
            persist()
            lastProgress.removeValue(forKey: taskID)
            transfers.removeValue(forKey: taskID)
            pump()
        } catch {
            try? FileManager.default.removeItem(at: url)
            failed(taskID, reason: "file_\((error as NSError).code)")
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        DownloadEvents.shared.begin()
        var destination: URL?
        var movedFile: URL?
        var failure = "http_\((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)"
        // The system deletes the temporary file when this callback returns, so move it now.
        if let filename = downloadTask.taskDescription,
           UUID(uuidString: (filename as NSString).deletingPathExtension) != nil,
           (filename as NSString).pathExtension == "m4a",
           let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) {
            do {
                let target = Self.root.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: location, to: target)
                movedFile = target
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
                destination = target
            } catch {
                failure = "file_\((error as NSError).code)"
                if let movedFile { try? FileManager.default.removeItem(at: movedFile) }
                destination = nil
            }
        }
        let result = destination
        let reason = failure
        let taskID = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self else { DownloadEvents.shared.end(); return }
            await self.finalize(taskID, url: result, failure: reason)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DownloadEvents.shared.begin()
        let taskID = task.taskIdentifier
        let code = (error as NSError).code
        let fileErrors = [URLError.Code.cannotWriteToFile.rawValue, URLError.Code.cannotCreateFile.rawValue, URLError.Code.cannotMoveFile.rawValue]
        let reason = (fileErrors.contains(code) ? "file_" : "network_") + String(code)
        Task { @MainActor [weak self] in self?.failed(taskID, reason: reason); DownloadEvents.shared.end() }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let taskID = downloadTask.taskIdentifier
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        Task { @MainActor [weak self] in
            guard let self, Date().timeIntervalSince(self.lastProgress[taskID] ?? .distantPast) >= 0.25,
                  let index = self.entries.firstIndex(where: { $0.taskID == taskID }) else { return }
            self.lastProgress[taskID] = .now
            self.entries[index].progress = fraction
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DownloadEvents.shared.finish()
    }
}
