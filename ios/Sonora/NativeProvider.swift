import Foundation
import Observation

/// Stable errors cross the native boundary; raw provider responses and signed URLs never reach alerts.
enum ProviderError: LocalizedError {
    case unavailable, timeout, signInRequired

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "ios-provider-error")
        case .timeout: String(localized: "ios-provider-timeout")
        case .signInRequired: String(localized: "ios-provider-sign-in-required")
        }
    }
}

/// Native response ownership lasts through cancellation until the bounded Rust callback arrives.
private final class NativeReply {
    let continuation: CheckedContinuation<Data, Error>
    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
}

private func receiveNativeReply(_ context: UnsafeMutableRawPointer?, _ json: UnsafeMutablePointer<CChar>?) {
    guard let context else { if let json { sonora_mobile_string_free(json) }; return }
    let reply = Unmanaged<NativeReply>.fromOpaque(context).takeRetainedValue()
    guard let json else { reply.continuation.resume(throwing: ProviderError.unavailable); return }
    let data = Data(bytes: json, count: strlen(json))
    sonora_mobile_string_free(json)
    reply.continuation.resume(returning: data)
}

/// Thin asynchronous adapter. All provider sockets and stream resolution run in the Rust core.
enum NativeProvider {
    private struct Envelope<Value: Decodable>: Decodable {
        let ok: Bool
        let data: Value?
        let error: String?
    }

    struct Song: Decodable {
        let id: String
        let title: String
        let artist: String
        let artwork_url: URL?
        let duration_seconds: Double?
        let available: Bool

        var track: MusicTrack {
            MusicTrack(id: "youtube:" + id, title: title, artist: artist, filename: "", addedAt: .now,
                       youtubeID: id, artworkURL: artwork_url, durationSeconds: duration_seconds, available: available)
        }
    }

    struct Stream: Decodable {
        let url: URL
        let mime: String
        let user_agent: String
        let duration_seconds: Double?
        let content_length: UInt64?
    }

    struct Lyrics: Decodable {
        let text: String?
        let source: String
    }

    static func search(_ query: String) async throws -> [MusicTrack] {
        let songs: [Song] = try await request(["operation": "search", "query": query])
        var seen: Set<String> = []
        return songs.map(\.track).filter { seen.insert($0.id).inserted }
    }

    static func resolve(_ id: String) async throws -> Stream {
        try await request(["operation": "resolve", "video_id": id])
    }

    static func lyrics(_ id: String) async throws -> Lyrics {
        try await request(["operation": "lyrics", "video_id": id])
    }

    private static func request<Value: Decodable>(_ request: [String: String]) async throws -> Value {
        let encoded = try JSONSerialization.data(withJSONObject: request)
        guard let input = String(data: encoded, encoding: .utf8) else { throw ProviderError.unavailable }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let reply = Unmanaged.passRetained(NativeReply(continuation))
            let result = input.withCString { sonora_mobile_request($0, reply.toOpaque(), receiveNativeReply) }
            if result != 0 {
                reply.release()
                continuation.resume(throwing: ProviderError.unavailable)
            }
        }
        try Task.checkCancellation()
        let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: data)
        guard envelope.ok, let value = envelope.data else {
            switch envelope.error {
            case "timeout": throw ProviderError.timeout
            case "sign_in_required": throw ProviderError.signInRequired
            default: throw ProviderError.unavailable
            }
        }
        return value
    }
}

/// Owns a cancellable lyrics request and discards results after a track changes or the sheet closes.
@MainActor @Observable
final class LyricsStore {
    private(set) var sheet: NativeProvider.Lyrics?
    private(set) var isLoading = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func load(_ id: String) {
        cancel()
        let generation = UUID()
        self.generation = generation
        isLoading = true
        error = nil
        sheet = nil
        task = Task { [weak self] in
            do {
                let lyrics = try await NativeProvider.lyrics(id)
                guard let self, self.generation == generation else { return }
                self.sheet = lyrics
                self.isLoading = false
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoading = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        generation = UUID()
        isLoading = false
    }
}

/// Holds search state and its task independently of view lifetime and ignores stale responses.
@MainActor @Observable
final class YouTubeSearch {
    var query = ""
    private(set) var tracks: [MusicTrack] = []
    private(set) var isLoading = false
    private(set) var hasSearched = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func submit(_ input: String) {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { clear(); return }
        task?.cancel()
        let generation = UUID()
        self.generation = generation
        tracks = []
        error = nil
        hasSearched = true
        isLoading = true
        task = Task { [weak self] in
            do {
                let tracks = try await NativeProvider.search(query)
                guard let self, self.generation == generation else { return }
                self.tracks = tracks
                self.isLoading = false
            } catch is CancellationError {
                // A newer search owns the screen; the old native callback still frees its response.
            } catch {
                guard let self, self.generation == generation else { return }
                self.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-provider-error")
                self.isLoading = false
            }
        }
    }

    func clear() {
        task?.cancel()
        generation = UUID()
        tracks = []
        error = nil
        hasSearched = false
        isLoading = false
    }
}
