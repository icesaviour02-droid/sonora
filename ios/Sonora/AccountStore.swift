import Foundation
import Observation
import Security
import SwiftUI
import WebKit

private struct SavedSession: Codable {
    let cookies: String
    let authuser: UInt8
    let pageID: String?
}

/// Carries only the OS status for diagnostics; account data never appears in error reports.
private struct AccountStorageError: Error { let status: OSStatus }

/// Stores the account session in this device's Keychain; credentials never enter preferences or logs.
private enum AccountKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.sonorahq.iphone.youtube",
         kSecAttrAccount as String: "session"]
    }

    static func read() throws -> SavedSession? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AccountStorageError(status: status) }
        guard let data = item as? Data else { throw CocoaError(.fileReadUnknown) }
        if let decoded = try? JSONDecoder().decode(SavedSession.self, from: data) {
            return decoded
        }
        guard let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadUnknown) }
        return SavedSession(cookies: value, authuser: 0, pageID: nil)
    }

    static func save(_ session: SavedSession) throws {
        let encoded = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw AccountStorageError(status: added) }
        } else if status != errSecSuccess { throw AccountStorageError(status: status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountStorageError(status: status) }
    }
}

/// Owns account verification, multi-channel discovery, and session restoration independently of the sign-in sheet's lifetime.
@MainActor @Observable
final class AccountStore {
    private(set) var name: String?
    private(set) var handle: String?
    private(set) var avatarURL: URL?
    private(set) var availableAccounts: [NativeProvider.Account] = []
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var revision = 0
    var error: String?
    @ObservationIgnored private var pendingCookies: String?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var sessionGeneration = 0

    func restore() async {
        guard isRestoring else { return }
        if operation == nil {
            operation = Task { [weak self] in
                guard let self else { return }
                await self.restoreSaved()
            }
        }
        await operation?.value
    }

    private func restoreSaved() async {
        defer { isRestoring = false }
        await NativeProvider.configure(cacheDir: SettingsStore.coreCacheRoot.path)
        do {
            guard let session = try AccountKeychain.read() else { return }
            let account = try await NativeProvider.authenticate(
                session.cookies,
                authuser: session.authuser,
                pageID: session.pageID,
                restoring: true
            )
            do {
                try AccountKeychain.save(SavedSession(cookies: account.cookies ?? session.cookies,
                    authuser: account.authuser ?? session.authuser, pageID: account.page_id ?? session.pageID))
            } catch {
                try? await NativeProvider.signOut()
                throw error
            }
            sessionGeneration += 1
            name = account.name
            handle = account.handle
            avatarURL = account.avatar_url.flatMap(URL.init(string:))
            error = nil
            startCookieRefresh(immediately: false)
        } catch {
            // Retain the Keychain item on a transient network failure so a retry can recover it.
            self.error = String(localized: "ios-account-restore-error")
        }
    }

    func retryRestore() {
        guard !isBusy, !isRestoring, name == nil else { return }
        isRestoring = true
        operation = Task { [weak self] in
            guard let self else { return }
            await self.restoreSaved()
        }
    }

    func rotateCookiesIfSignedIn() {
        guard name != nil, !isBusy, !isRestoring else { return }
        startCookieRefresh(immediately: true)
    }

    /// Rotation and Keychain persistence share one cancelable task and cannot cross sign-out.
    private func startCookieRefresh(immediately: Bool) {
        refreshTask?.cancel()
        let generation = sessionGeneration
        refreshTask = Task { [weak self] in
            var shouldWait = !immediately
            while !Task.isCancelled {
                if shouldWait {
                    do { try await Task.sleep(for: .seconds(600)) }
                    catch { return }
                }
                shouldWait = true
                guard let self, self.sessionGeneration == generation, self.name != nil else { return }
                let cookies = await NativeProvider.rotateCookies()
                guard !Task.isCancelled, self.sessionGeneration == generation, self.name != nil else { return }
                guard let cookies else { continue }
                do {
                    guard let saved = try AccountKeychain.read() else { return }
                    try AccountKeychain.save(SavedSession(cookies: cookies, authuser: saved.authuser, pageID: saved.pageID))
                } catch { self.error = String(localized: "ios-account-save-error") }
            }
        }
    }

    func signIn(_ cookies: String, authuser: UInt8 = 0, pageID: String? = nil, discoverChannels: Bool = true) {
        guard !isBusy, !isRestoring, name == nil else { return }
        isBusy = true
        error = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do {
                if discoverChannels {
                    let accounts = (try? await NativeProvider.listAccounts(cookies)) ?? []
                    if accounts.count > 1 {
                        self.pendingCookies = cookies
                        self.availableAccounts = accounts
                        return
                    }
                    if let first = accounts.first {
                        try await self.completeSignIn(
                            cookies: cookies,
                            authuser: first.authuser ?? 0,
                            pageID: first.page_id
                        )
                        return
                    }
                }
                try await self.completeSignIn(cookies: cookies, authuser: authuser, pageID: pageID)
            } catch {
                self.error = String(localized: "ios-account-sign-in-error")
            }
        }
    }

    func selectAccount(_ account: NativeProvider.Account) {
        guard let cookies = pendingCookies else { return }
        availableAccounts = []
        pendingCookies = nil
        signIn(cookies, authuser: account.authuser ?? 0, pageID: account.page_id, discoverChannels: false)
    }

    func cancelAccountSelection() {
        availableAccounts = []
        pendingCookies = nil
    }

    private func completeSignIn(cookies: String, authuser: UInt8, pageID: String?) async throws {
        let account = try await NativeProvider.authenticate(cookies, authuser: authuser, pageID: pageID)
        do {
            try AccountKeychain.save(SavedSession(
                cookies: account.cookies ?? cookies,
                authuser: account.authuser ?? authuser,
                pageID: account.page_id ?? pageID
            ))
        } catch {
            try? await NativeProvider.signOut()
            self.error = String(localized: "ios-account-save-error")
            return
        }
        self.name = account.name
        self.sessionGeneration += 1
        self.handle = account.handle
        self.avatarURL = account.avatar_url.flatMap(URL.init(string:))
        self.availableAccounts = []
        self.pendingCookies = nil
        self.revision += 1
        startCookieRefresh(immediately: false)
    }

    func signOut() {
        guard !isBusy, !isRestoring else { return }
        isBusy = true
        error = nil
        sessionGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do {
                try AccountKeychain.remove()
                try await NativeProvider.signOut()
                self.name = nil
                self.handle = nil
                self.avatarURL = nil
                self.availableAccounts = []
                self.pendingCookies = nil
                self.revision += 1
            } catch { self.error = String(localized: "ios-account-sign-out-error") }
        }
    }

    #if DEBUG
    /// Exercises the actual simulator Keychain without a Google account or credential exports.
    func reviewSessionStorage() {
        guard ProcessInfo.processInfo.arguments.contains("--sonora-review-url") else { return }
        var checks: [String: Bool] = [:]
        var osStatus: OSStatus?
        do {
            let previous = try AccountKeychain.read()
            defer {
                if let previous { try? AccountKeychain.save(previous) }
                else { try? AccountKeychain.remove() }
            }
            try AccountKeychain.save(SavedSession(cookies: "SAPISID=sonora-original", authuser: 2, pageID: "sonora-review-page"))
            checks["session_round_trip"] = try AccountKeychain.read()?.cookies == "SAPISID=sonora-original"
            try AccountKeychain.save(SavedSession(cookies: "SAPISID=sonora-rotated", authuser: 2, pageID: "sonora-review-page"))
            let updated = try AccountKeychain.read()
            checks["rotated_credentials_replace_original"] = updated?.cookies == "SAPISID=sonora-rotated"
            checks["account_selection_preserved"] = updated?.authuser == 2 && updated?.pageID == "sonora-review-page"
            try AccountKeychain.remove()
            checks["signed_out_credentials_removed"] = try AccountKeychain.read() == nil
        } catch {
            checks["keychain_operation"] = false
            osStatus = (error as? AccountStorageError)?.status
        }
        var report: [String: Any] = ["passed": checks.count == 4 && checks.values.allSatisfy { $0 }, "checks": checks]
        if let osStatus { report["os_status"] = osStatus }
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("account-storage-review.json"), options: .atomic)
        }
    }
    #endif
}

/// Keeps Google's sign-in page isolated from other apps. It uses the normal WebKit identity;
/// a provider rejection is shown honestly rather than disguised with another browser identity.
@MainActor @Observable
private final class AccountBrowser: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var error: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
    }

    func cookies(_ completion: @escaping (String) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let pairs = cookies.filter {
                let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return domain == "youtube.com" || domain.hasSuffix(".youtube.com")
            }.map { $0.name + "=" + $0.value }.joined(separator: "; ")
            completion(pairs)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let host = url?.host?.lowercased() ?? ""
        let trusted = ["youtube.com", "google.com", "gstatic.com", "googleusercontent.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
        if url?.scheme == "https" && trusted { decisionHandler(.allow) }
        else { error = String(localized: "ios-account-page-unavailable"); decisionHandler(.cancel) }
    }
}

private struct AccountBrowserView: UIViewRepresentable {
    let browser: AccountBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Hosts provider sign-in, brand-channel selection, and the desktop-compatible existing-session fallback.
struct AccountSignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var browser = AccountBrowser()
    @State private var showSessionImport = false
    @State private var sessionHeader = ""

    var body: some View {
        NavigationStack {
            Group {
                if !account.availableAccounts.isEmpty {
                    List {
                        Section("ios-account-choose-channel") {
                            ForEach(account.availableAccounts) { item in
                                Button {
                                    account.selectAccount(item)
                                } label: {
                                    HStack(spacing: Layout.spacing) {
                                        AsyncImage(url: item.avatar_url.flatMap(URL.init(string:))) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "person.crop.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).foregroundStyle(.primary).appFont(.body, weight: .medium)
                                            if let handle = item.handle, !handle.isEmpty {
                                                Text(handle).appFont(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .appFont(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .disabled(account.isBusy)
                            }
                        }
                    }
                } else {
                    VStack(spacing: Layout.compact) {
                        AccountBrowserView(browser: browser)
                        if let error = account.error ?? browser.error {
                            Text(error).foregroundStyle(.secondary).padding(.horizontal, Layout.spacing)
                        }
                        if account.isBusy { ProgressView("ios-account-verifying") }
                        Text("ios-account-data-description")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Layout.spacing)
                        Button("ios-account-continue") {
                            browser.cookies { header in Task { @MainActor in account.signIn(header) } }
                        }
                        .buttonStyle(.glassProminent)
                        .frame(minHeight: Layout.control)
                        .disabled(account.isBusy)
                        Button("ios-account-import-session") { showSessionImport = true }
                            .frame(minHeight: Layout.control)
                            .disabled(account.isBusy)
                    }
                }
            }
            .appNavigationTitle("ios-account-sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios-done") {
                        account.cancelAccountSelection()
                        dismiss()
                    }
                    .disabled(account.isBusy)
                }
            }
            .onChange(of: account.name) { _, name in if name != nil { dismiss() } }
            .sheet(isPresented: $showSessionImport) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("ios-account-session-header", text: $sessionHeader)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("ios-account-continue") {
                                account.signIn(sessionHeader)
                                sessionHeader = ""
                            }
                            .disabled(account.isBusy || sessionHeader.isEmpty)
                            if account.isBusy { ProgressView("ios-account-verifying") }
                            if let error = account.error { Text(error).foregroundStyle(.secondary) }
                        } footer: { Text("ios-account-session-description") }
                    }
                    .appNavigationTitle("ios-account-import-session")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("ios-done") { showSessionImport = false; sessionHeader = "" }.disabled(account.isBusy)
                        }
                    }
                    .onChange(of: account.name) { _, name in if name != nil { showSessionImport = false; dismiss() } }
                    .onChange(of: account.availableAccounts) { _, items in
                        if !items.isEmpty { showSessionImport = false }
                    }
                }
                .interactiveDismissDisabled(account.isBusy)
            }
        }
        .interactiveDismissDisabled(account.isBusy)
    }
}
