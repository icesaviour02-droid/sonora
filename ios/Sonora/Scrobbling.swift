import CryptoKit
import Foundation

/// Credentials stay in memory and Keychain. Durable jobs identify an account by a one-way digest.
struct ScrobbleConfiguration: Sendable {
    let listenBrainzToken: String
    let malojaURL: String
    let malojaKey: String

    var targets: [ScrobbleTarget] {
        var result: [ScrobbleTarget] = []
        if !listenBrainzToken.isEmpty {
            result.append(ScrobbleTarget(service: .listenbrainz, server: "https://api.listenbrainz.org", token: listenBrainzToken))
        }
        let server = malojaURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !server.isEmpty, !malojaKey.isEmpty {
            let root = server.contains("://") ? server : "https://" + server
            if let url = URL(string: root), ["https", "http"].contains(url.scheme ?? ""), url.host != nil {
                result.append(ScrobbleTarget(service: .maloja, server: root, token: malojaKey))
            }
        }
        return result
    }
}

enum ScrobbleService: String, Codable, Sendable { case listenbrainz, maloja }

struct ScrobbleTarget: Sendable {
    let service: ScrobbleService
    let server: String
    let token: String
    var fingerprint: String {
        SHA256.hash(data: Data((service.rawValue + "\0" + server + "\0" + token).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ScrobbleListen: Codable, Sendable {
    let id: UUID
    let artist: String
    let title: String
    let album: String?
    let duration: Double
    let startedAt: Date
}

/// An injectable transport keeps acceptance checks off real accounts and external services.
protocol ScrobbleTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Bool
}

private struct ScrobbleHTTP: ScrobbleTransport {
    func send(_ request: URLRequest) async throws -> Bool {
        let (data, response) = try await NetworkAccess.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
        if request.url?.path.hasSuffix("newscrobble") == true {
            let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return ["ok", "success"].contains(answer?["status"] as? String ?? "")
        }
        return true
    }
}

/// Keeps per-service listens until acknowledged, so one offline service cannot drop another's listen.
actor ScrobbleOutbox {
    static let shared = ScrobbleOutbox()
    private struct Job: Codable {
        let service: ScrobbleService
        let account: String
        let listen: ScrobbleListen
        var attempts: Int = 0
        var retryAt: Date = .distantPast
    }
    private let file: URL
    private let transport: any ScrobbleTransport
    private var jobs: [Job] = []
    private var writable = true
    private var sending = false

    init(file: URL = URL.applicationSupportDirectory.appendingPathComponent("State/scrobble-outbox.json"),
         transport: any ScrobbleTransport = ScrobbleHTTP()) {
        self.file = file
        self.transport = transport
        if FileManager.default.fileExists(atPath: file.path) {
            do { jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: file)) }
            catch { writable = false }
        }
    }

    /// Enqueue first, then submit. No authentication secret is ever serialized with a job.
    func enqueue(_ listen: ScrobbleListen, targets: [ScrobbleTarget]) throws {
        guard writable else { throw CocoaError(.fileReadCorruptFile) }
        var next = jobs
        for target in targets where !next.contains(where: { $0.account == target.fingerprint && $0.listen.id == listen.id }) {
            next.append(Job(service: target.service, account: target.fingerprint, listen: listen))
        }
        try commit(next)
    }

    /// Serializes submissions; retry state is durable, while now-playing reports are never queued.
    func flush(targets: [ScrobbleTarget], force: Bool = false, now: Date = .now) async throws -> Int {
        guard writable else { throw CocoaError(.fileReadCorruptFile) }
        guard !sending else { return jobs.count }
        sending = true
        defer { sending = false }
        let ids = jobs.filter { force || $0.retryAt <= now }.map { ($0.listen.id, $0.account) }
        for (id, account) in ids {
            try Task.checkCancellation()
            guard let index = jobs.firstIndex(where: { $0.listen.id == id && $0.account == account }),
                  let target = targets.first(where: { $0.fingerprint == account }) else { continue }
            let job = jobs[index]
            let accepted: Bool
            do { accepted = try await transport.send(Self.request(job.listen, target: target, nowPlaying: false)) }
            catch is CancellationError { throw CancellationError() }
            catch { accepted = false }
            // An enqueue can run while HTTP awaits. Find the job again before changing it.
            guard let current = jobs.firstIndex(where: { $0.listen.id == id && $0.account == account }) else { continue }
            var next = jobs
            if accepted { next.remove(at: current) }
            else {
                next[current].attempts += 1
                next[current].retryAt = now.addingTimeInterval(min(1_800, 30 * pow(2, Double(min(next[current].attempts - 1, 6)))))
            }
            try commit(next)
        }
        return jobs.filter { job in targets.contains { $0.fingerprint == job.account } }.count
    }

    func nowPlaying(_ listen: ScrobbleListen, targets: [ScrobbleTarget]) async {
        for target in targets where target.service == .listenbrainz {
            guard !Task.isCancelled else { return }
            if let request = try? Self.request(listen, target: target, nowPlaying: true) { _ = try? await transport.send(request) }
        }
    }

    private func commit(_ next: [Job]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        jobs = next
    }

    /// Payload fields match the desktop's ListenBrainz and Maloja implementations.
    private static func request(_ listen: ScrobbleListen, target: ScrobbleTarget, nowPlaying: Bool) throws -> URLRequest {
        let path = target.service == .listenbrainz ? "/1/submit-listens" : "/apis/mlj_1/newscrobble"
        guard let url = URL(string: target.server + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any]
        let timestamp = Int(listen.startedAt.timeIntervalSince1970)
        switch target.service {
        case .listenbrainz:
            request.setValue("Token " + target.token, forHTTPHeaderField: "Authorization")
            var metadata: [String: Any] = ["artist_name": listen.artist, "track_name": listen.title,
                "additional_info": ["duration_ms": Int(listen.duration * 1_000), "media_player": "Sonora", "submission_client": "Sonora"]]
            if let album = listen.album, !album.isEmpty { metadata["release_name"] = album }
            var payload: [String: Any] = ["track_metadata": metadata]
            if !nowPlaying { payload["listened_at"] = timestamp }
            body = ["listen_type": nowPlaying ? "playing_now" : "single", "payload": [payload]]
        case .maloja:
            body = ["key": target.token, "artists": [listen.artist], "title": listen.title,
                "length": Int(listen.duration), "time": timestamp]
            if let album = listen.album, !album.isEmpty { body["album"] = album }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

#if DEBUG
/// Returns scripted acknowledgements and checks real request payloads without contacting accounts.
private actor ScrobbleReviewTransport: ScrobbleTransport {
    private var answers: [Bool]
    private(set) var requests: [URLRequest] = []
    init(_ answers: [Bool]) { self.answers = answers }
    func send(_ request: URLRequest) async throws -> Bool {
        requests.append(request)
        return answers.isEmpty ? true : answers.removeFirst()
    }
}

extension ScrobbleOutbox {
    /// Checks durable retry/account isolation and desktop-compatible payloads on the Apple runtime.
    static func review() async -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listens.json")
        let transport = ScrobbleReviewTransport([false, true, true])
        let outbox = ScrobbleOutbox(file: file, transport: transport)
        let config = ScrobbleConfiguration(listenBrainzToken: "review-token", malojaURL: "https://maloja.invalid", malojaKey: "review-key")
        let listen = ScrobbleListen(id: UUID(), artist: "Sonora Review", title: "Generated Tone", album: nil, duration: 120,
                                    startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        do {
            try await outbox.enqueue(listen, targets: config.targets)
            try await outbox.enqueue(listen, targets: config.targets)
            let before = try JSONDecoder().decode([Job].self, from: Data(contentsOf: file))
            checks["deduplicate_pending_occurrence"] = before.count == 2
            let json = try String(contentsOf: file, encoding: .utf8)
            checks["no_saved_credentials"] = !json.contains("review-token") && !json.contains("review-key")
            let remaining = try await outbox.flush(targets: config.targets)
            checks["independent_service_acknowledgements"] = remaining == 1
            let requests = await transport.requests
            let lb = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
            let payload = (lb["payload"] as! [[String: Any]])[0]
            let maloja = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as! [String: Any]
            checks["original_listen_timestamp"] = payload["listened_at"] as? Int == 1_700_000_000 && maloja["time"] as? Int == 1_700_000_000
            checks["desktop_payloads"] = lb["listen_type"] as? String == "single" && maloja["artists"] as? [String] == [listen.artist] && maloja["length"] as? Int == 120
            let restored = ScrobbleOutbox(file: file, transport: transport)
            _ = try await restored.flush(targets: config.targets)
            checks["retry_backoff_restores"] = await transport.requests.count == 2
            let changed = ScrobbleConfiguration(listenBrainzToken: "different-token", malojaURL: "", malojaKey: "")
            _ = try await restored.flush(targets: changed.targets, force: true)
            checks["account_isolation"] = await transport.requests.count == 2
            let final = try await restored.flush(targets: config.targets, force: true)
            let saved = try JSONDecoder().decode([Job].self, from: Data(contentsOf: file))
            checks["retry_after_relaunch"] = final == 0 && saved.isEmpty
            await restored.nowPlaying(listen, targets: config.targets)
            let last = await transport.requests.last!
            let now = try JSONSerialization.jsonObject(with: last.httpBody!) as! [String: Any]
            let current = (now["payload"] as! [[String: Any]])[0]
            checks["now_playing_without_timestamp"] = now["listen_type"] as? String == "playing_now" && current["listened_at"] == nil
        } catch { checks["outbox_completed"] = false }
        return checks
    }
}
#endif
