import Foundation

/// One thread-safe gate for deliberate offline mode and observed connectivity, including in-flight requests.
final class NetworkAccess: @unchecked Sendable {
    static let shared = NetworkAccess()
    private let lock = NSLock()
    private var offline = UserDefaults.standard.bool(forKey: "sonora.offlineMode")
    private var cancellations: [UUID: () -> Void] = [:]

    var isOffline: Bool { lock.lock(); defer { lock.unlock() }; return offline }

    func update(offline: Bool) {
        lock.lock()
        self.offline = offline
        let pending = offline ? Array(cancellations.values) : []
        lock.unlock()
        pending.forEach { $0() }
    }

    /// Registration closes the race between starting a request and switching offline.
    func register(_ cancel: @escaping () -> Void) throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        guard !offline else { throw ProviderError.offline }
        let id = UUID(); cancellations[id] = cancel; return id
    }

    func unregister(_ id: UUID) { lock.lock(); cancellations[id] = nil; lock.unlock() }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard !isOffline else { throw ProviderError.offline }
        let work = Task { try await URLSession.shared.data(for: request) }
        let id: UUID
        do { id = try register { work.cancel() } }
        catch { work.cancel(); throw error }
        defer { unregister(id) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
