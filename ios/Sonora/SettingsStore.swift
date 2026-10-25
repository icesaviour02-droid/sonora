import Foundation
import Observation
import Security
import SwiftUI
import WebKit

/// Stores scrobbling tokens in this device's Keychain so API tokens never enter UserDefaults.
private enum ScrobbleKeychain {
    static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.sonorahq.iphone.scrobble",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.sonorahq.iphone.scrobble",
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// Persists desktop-equivalent Sonora settings, pins, listening history, and scrobbling on iPhone.
@MainActor @Observable
final class SettingsStore {
    var streamingQuality: AudioQuality {
        didSet { UserDefaults.standard.set(streamingQuality.rawValue, forKey: "sonora.settings.streamingQuality") }
    }
    var downloadQuality: AudioQuality {
        didSet { UserDefaults.standard.set(downloadQuality.rawValue, forKey: "sonora.settings.downloadQuality") }
    }
    var normalizeVolume: Bool {
        didSet { UserDefaults.standard.set(normalizeVolume, forKey: "sonora.settings.normalizeVolume") }
    }
    var autoplayRadio: Bool {
        didSet { UserDefaults.standard.set(autoplayRadio, forKey: "sonora.settings.autoplayRadio") }
    }
    var equalizerEnabled: Bool {
        didSet { UserDefaults.standard.set(equalizerEnabled, forKey: "sonora.settings.equalizerEnabled") }
    }
    var equalizerPreset: EqualizerPreset {
        didSet {
            UserDefaults.standard.set(equalizerPreset.rawValue, forKey: "sonora.settings.equalizerPreset")
            if equalizerPreset != .custom {
                preampDB = equalizerPreset.preampDB
                bassDB = equalizerPreset.bassDB
                trebleDB = equalizerPreset.trebleDB
            }
        }
    }
    var preampDB: Double {
        didSet { UserDefaults.standard.set(preampDB, forKey: "sonora.settings.preampDB") }
    }
    var bassDB: Double {
        didSet { UserDefaults.standard.set(bassDB, forKey: "sonora.settings.bassDB") }
    }
    var trebleDB: Double {
        didSet { UserDefaults.standard.set(trebleDB, forKey: "sonora.settings.trebleDB") }
    }
    var sleepTimer: SleepTimerOption = .off
    var sleepTimerDeadline: Date?
    var syncedLyrics: Bool {
        didSet { UserDefaults.standard.set(syncedLyrics, forKey: "sonora.settings.syncedLyrics") }
    }
    var blurInactiveLyrics: Bool {
        didSet { UserDefaults.standard.set(blurInactiveLyrics, forKey: "sonora.settings.blurInactiveLyrics") }
    }
    var romanizedLyrics: Bool {
        didSet { UserDefaults.standard.set(romanizedLyrics, forKey: "sonora.settings.romanizedLyrics") }
    }
    var localFileLyrics: Bool {
        didSet { UserDefaults.standard.set(localFileLyrics, forKey: "sonora.settings.localFileLyrics") }
    }
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "sonora.settings.theme") }
    }
    var animatedArtwork: Bool {
        didSet { UserDefaults.standard.set(animatedArtwork, forKey: "sonora.settings.animatedArtwork") }
    }
    var scrobbleEnabled: Bool {
        didSet { UserDefaults.standard.set(scrobbleEnabled, forKey: "sonora.settings.scrobbleEnabled") }
    }
    var listenBrainzToken: String {
        didSet { ScrobbleKeychain.save(listenBrainzToken.trimmingCharacters(in: .whitespacesAndNewlines), account: "listenbrainz") }
    }
    var malojaURL: String {
        didSet { UserDefaults.standard.set(malojaURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "sonora.settings.malojaURL") }
    }
    var malojaKey: String {
        didSet { ScrobbleKeychain.save(malojaKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "maloja") }
    }

    private(set) var pins: [PinnedItem] = []
    private(set) var history: [MusicTrack] = []
    private(set) var cacheBytes: UInt64 = 0

    private static var stateRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("State", isDirectory: true)
    }
    static var coreCacheRoot: URL {
        URL.cachesDirectory.appendingPathComponent("SonoraCore", isDirectory: true)
    }
    private var pinsURL: URL { Self.stateRoot.appendingPathComponent("pins.json") }
    private var historyURL: URL { Self.stateRoot.appendingPathComponent("history.json") }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "sonora.settings.streamingQuality": AudioQuality.high.rawValue,
            "sonora.settings.downloadQuality": AudioQuality.high.rawValue,
            "sonora.settings.normalizeVolume": true,
            "sonora.settings.autoplayRadio": true,
            "sonora.settings.equalizerEnabled": false,
            "sonora.settings.equalizerPreset": EqualizerPreset.flat.rawValue,
            "sonora.settings.preampDB": 0.0,
            "sonora.settings.bassDB": 0.0,
            "sonora.settings.trebleDB": 0.0,
            "sonora.settings.syncedLyrics": true,
            "sonora.settings.blurInactiveLyrics": true,
            "sonora.settings.romanizedLyrics": true,
            "sonora.settings.localFileLyrics": true,
            "sonora.settings.theme": AppTheme.system.rawValue,
            "sonora.settings.animatedArtwork": true,
            "sonora.settings.scrobbleEnabled": false,
            "sonora.settings.malojaURL": ""
        ])
        streamingQuality = AudioQuality(rawValue: defaults.string(forKey: "sonora.settings.streamingQuality") ?? "") ?? .high
        downloadQuality = AudioQuality(rawValue: defaults.string(forKey: "sonora.settings.downloadQuality") ?? "") ?? .high
        normalizeVolume = defaults.bool(forKey: "sonora.settings.normalizeVolume")
        autoplayRadio = defaults.bool(forKey: "sonora.settings.autoplayRadio")
        equalizerEnabled = defaults.bool(forKey: "sonora.settings.equalizerEnabled")
        equalizerPreset = EqualizerPreset(rawValue: defaults.string(forKey: "sonora.settings.equalizerPreset") ?? "") ?? .flat
        preampDB = defaults.double(forKey: "sonora.settings.preampDB")
        bassDB = defaults.double(forKey: "sonora.settings.bassDB")
        trebleDB = defaults.double(forKey: "sonora.settings.trebleDB")
        syncedLyrics = defaults.bool(forKey: "sonora.settings.syncedLyrics")
        blurInactiveLyrics = defaults.bool(forKey: "sonora.settings.blurInactiveLyrics")
        romanizedLyrics = defaults.bool(forKey: "sonora.settings.romanizedLyrics")
        localFileLyrics = defaults.bool(forKey: "sonora.settings.localFileLyrics")
        theme = AppTheme(rawValue: defaults.string(forKey: "sonora.settings.theme") ?? "") ?? .system
        animatedArtwork = defaults.bool(forKey: "sonora.settings.animatedArtwork")
        scrobbleEnabled = defaults.bool(forKey: "sonora.settings.scrobbleEnabled")
        listenBrainzToken = ScrobbleKeychain.read(account: "listenbrainz")
        malojaURL = defaults.string(forKey: "sonora.settings.malojaURL") ?? ""
        malojaKey = ScrobbleKeychain.read(account: "maloja")

        try? FileManager.default.createDirectory(at: Self.stateRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.coreCacheRoot, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: pinsURL),
           let decoded = try? JSONDecoder().decode([PinnedItem].self, from: data) {
            pins = decoded
        }
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([MusicTrack].self, from: data) {
            history = decoded
        }
        measureCache()
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimer = option
        if let minutes = option.minutes {
            sleepTimerDeadline = Date().addingTimeInterval(Double(minutes * 60))
        } else {
            sleepTimerDeadline = nil
        }
    }

    func resetEqualizer() {
        equalizerPreset = .flat
        preampDB = 0
        bassDB = 0
        trebleDB = 0
    }

    func isPinned(_ id: String) -> Bool {
        pins.contains { $0.id == id }
    }

    func togglePin(_ item: PinnedItem) {
        if let index = pins.firstIndex(where: { $0.id == item.id }) {
            pins.remove(at: index)
        } else {
            pins.insert(item, at: 0)
        }
        savePins()
    }

    func pinTrack(_ track: MusicTrack) {
        togglePin(PinnedItem(
            id: track.id,
            kind: .track,
            title: track.title,
            subtitle: track.artist,
            artworkURL: track.artworkURL,
            targetID: track.youtubeID ?? track.id,
            track: track
        ))
    }

    func recordHistory(_ track: MusicTrack) {
        history.removeAll { $0.id == track.id }
        history.insert(track, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        saveHistory()
    }

    func removeFromHistory(_ track: MusicTrack) {
        history.removeAll { $0.id == track.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func clearAccountData() {
        history.removeAll { $0.youtubeID != nil }
        pins.removeAll { $0.kind != .track || $0.track?.youtubeID != nil }
        saveHistory()
        savePins()
    }

    func measureCache() {
        var total = UInt64(URLCache.shared.currentDiskUsage)
        if let enumerator = FileManager.default.enumerator(at: Self.coreCacheRoot, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += UInt64(max(0, size))
                }
            }
        }
        cacheBytes = total
    }

    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let resolved = Self.coreCacheRoot.appendingPathComponent("resolved.json")
        try? FileManager.default.removeItem(at: resolved)
        measureCache()
    }

    func submitScrobble(_ track: MusicTrack) {
        guard scrobbleEnabled else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let lbToken = listenBrainzToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lbToken.isEmpty, let url = URL(string: "https://api.listenbrainz.org/1/submit-listens") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Token \(lbToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "listen_type": "single",
                "payload": [[
                    "listened_at": timestamp,
                    "track_metadata": [
                        "artist_name": track.artist,
                        "track_name": track.title,
                        "release_name": track.albumTitle ?? ""
                    ]
                ]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            Task.detached { _ = try? await URLSession.shared.data(for: request) }
        }
        let mURL = malojaURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let mKey = malojaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mURL.isEmpty, !mKey.isEmpty, let url = URL(string: "\(mURL)/apis/mlj_1/newscrobble") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "key": mKey,
                "artist": track.artist,
                "title": track.title,
                "album": track.albumTitle ?? "",
                "time": timestamp
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            Task.detached { _ = try? await URLSession.shared.data(for: request) }
        }
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) {
            try? data.write(to: pinsURL, options: .atomic)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}

/// Mints YouTube proof-of-origin tokens in a hidden WebKit page using the same BotGuard script as desktop Sonora.
@MainActor
final class PoTokenMinter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var pollTask: Task<Void, Never>?
    private var warmed = false

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let binding = await NativeProvider.poTokenWanted()
                if let binding, !binding.isEmpty {
                    await self.mint(binding: binding)
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = contentController
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        view.navigationDelegate = self
        webView = view
        return view
    }

    private func mint(binding: String) async {
        let view = ensureWebView()
        let escaped = binding.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? binding
        if warmed {
            if let encoded = try? JSONEncoder().encode(binding),
               let literal = String(data: encoded, encoding: .utf8) {
                _ = try? await view.evaluateJavaScript("window.sonoraPoToken && window.sonoraPoToken(\(literal))")
            }
        } else if let url = URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw?binding=\(escaped)") {
            view.load(URLRequest(url: url))
            warmed = true
        }

        let prefix = escaped + ":"
        let deadline = Date().addingTimeInterval(32)
        while Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard let cookie = cookies.first(where: { $0.name == "SONORA_POT" && $0.value.hasPrefix(prefix) }) else {
                continue
            }
            let answer = String(cookie.value.dropFirst(prefix.count))
            if answer.hasPrefix("!") {
                warmed = false
                await NativeProvider.poTokenFailed()
                return
            } else if !answer.isEmpty {
                await NativeProvider.poTokenGive(binding: binding, token: answer)
                return
            }
        }
        warmed = false
        await NativeProvider.poTokenFailed()
    }

    private static let script = #"""
    (function () {
      "use strict";
      var COOKIE = "SONORA_POT";
      var FAILED = "!";
      var SEPARATOR = ":";
      var HOLDER = "havuokmhhs-0";
      var SLOT = "bevasrs";
      var PATIENCE = 30000;
      var STEP = 200;

      function answer(binding, value) {
        document.cookie = COOKIE + "=" + encodeURIComponent(binding) + SEPARATOR + value + "; path=/; max-age=120";
      }
      function fail(binding, why) {
        answer(binding, FAILED + String(why).slice(0, 180).replace(/[;,\s]+/g, " "));
      }
      function message(error) {
        return error && error.message ? error.message : error;
      }
      var wanted = (function () {
        var found = /[?&]binding=([^&]+)/.exec(location.search);
        var value = found ? decodeURIComponent(found[1]) : null;
        try {
          if (value) sessionStorage.setItem(COOKIE, value);
          else value = sessionStorage.getItem(COOKIE);
        } catch (error) {}
        return value;
      })();
      function answered(binding) {
        var found = new RegExp("(?:^|; )" + COOKIE + "=([^;]*)").exec(document.cookie);
        var prefix = encodeURIComponent(binding) + SEPARATOR;
        return !!found && found[1].indexOf(prefix) === 0 && found[1].charAt(prefix.length) !== FAILED;
      }
      function holding(name) {
        try {
          var value = window[name];
          if (!value || typeof value !== "object" || value.window === value) return null;
          for (var key in value) {
            var inner = value[key];
            if (inner && typeof inner.wpc === "function") return inner.wpc;
          }
        } catch (error) {}
        return null;
      }
      function client() {
        var holder = window[HOLDER];
        if (holder && holder[SLOT] && typeof holder[SLOT].wpc === "function") {
          return holder[SLOT].wpc;
        }
        var names = Object.getOwnPropertyNames(window);
        for (var at = 0; at < names.length; at++) {
          var found = holding(names[at]);
          if (found) return found;
        }
        return null;
      }
      function mint(binding) {
        if (!binding) return fail("", "no binding to mint for");
        var started = Date.now();
        (function attempt() {
          var overdue = Date.now() - started > PATIENCE;
          var made = client();
          if (!made) {
            if (overdue) return fail(binding, "the page has no minting client");
            return setTimeout(attempt, STEP);
          }
          made()
            .then(function (minter) { return minter.mws({ c: binding, mc: false, me: false }); })
            .then(function (token) {
              if (!token) throw new Error("the minting client returned nothing");
              answer(binding, token);
            })
            .catch(function (error) {
              if (String(error).indexOf("SDF:notready") >= 0 && !overdue) {
                return setTimeout(attempt, STEP);
              }
              fail(binding, message(error));
            });
        })();
      }
      try { Object.defineProperty(window, "sonoraPoToken", { value: mint }); } catch (error) {}
      try {
        if (!wanted) fail("", "no binding in the url");
        else if (!answered(wanted)) mint(wanted);
      } catch (error) {
        fail(wanted || "", message(error));
      }
    })();
    """#
}
