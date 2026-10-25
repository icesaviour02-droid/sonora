import Foundation
import Observation
import Security
import SwiftUI
import WebKit

/// Stores the account session in this device's Keychain; credentials never enter preferences or logs.
private enum AccountKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.sonorahq.iphone.youtube",
         kSecAttrAccount as String: "session"]
    }

    static func read() throws -> String? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadUnknown) }
        return value
    }

    static func save(_ value: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Owns account verification and restoration independently of the sign-in sheet's lifetime.
@MainActor @Observable
final class AccountStore {
    private(set) var name: String?
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var revision = 0
    var error: String?
    @ObservationIgnored private var operation: Task<Void, Never>?

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
        do {
            guard let cookies = try AccountKeychain.read() else { return }
            name = try await NativeProvider.authenticate(cookies).name
            error = nil
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

    func signIn(_ cookies: String) {
        guard !isBusy, !isRestoring, name == nil else { return }
        isBusy = true
        error = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do {
                let account = try await NativeProvider.authenticate(cookies)
                do { try AccountKeychain.save(cookies) }
                catch {
                    try? await NativeProvider.signOut()
                    self.error = String(localized: "ios-account-save-error")
                    return
                }
                self.name = account.name
                self.revision += 1
            } catch {
                self.error = String(localized: "ios-account-sign-in-error")
            }
        }
    }

    func signOut() {
        guard !isBusy, !isRestoring else { return }
        isBusy = true
        error = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do {
                try AccountKeychain.remove()
                try await NativeProvider.signOut()
                self.name = nil
                self.revision += 1
            } catch { self.error = String(localized: "ios-account-sign-out-error") }
        }
    }
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

/// Hosts provider sign-in and the desktop-compatible existing-session fallback.
struct AccountSignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var browser = AccountBrowser()
    @State private var showSessionImport = false
    @State private var sessionHeader = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: Layout.compact) {
                AccountBrowserView(browser: browser)
                if let error = account.error ?? browser.error { Text(error).foregroundStyle(.secondary).padding(.horizontal, Layout.spacing) }
                if account.isBusy { ProgressView("ios-account-verifying") }
                Text("ios-account-data-description").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, Layout.spacing)
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
            .navigationTitle("ios-account-sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ios-done") { dismiss() }.disabled(account.isBusy) } }
            .onChange(of: account.name) { _, name in if name != nil { dismiss() } }
            .sheet(isPresented: $showSessionImport) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("ios-account-session-header", text: $sessionHeader)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("ios-account-continue") { account.signIn(sessionHeader); sessionHeader = "" }
                                .disabled(account.isBusy || sessionHeader.isEmpty)
                            if account.isBusy { ProgressView("ios-account-verifying") }
                            if let error = account.error { Text(error).foregroundStyle(.secondary) }
                        } footer: { Text("ios-account-session-description") }
                    }
                    .navigationTitle("ios-account-import-session")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ios-done") { showSessionImport = false; sessionHeader = "" }.disabled(account.isBusy) } }
                    .onChange(of: account.name) { _, name in if name != nil { showSessionImport = false; dismiss() } }
                }
                .interactiveDismissDisabled(account.isBusy)
            }
        }
        .interactiveDismissDisabled(account.isBusy)
    }
}
