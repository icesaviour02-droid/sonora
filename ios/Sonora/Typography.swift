import CoreText
import Foundation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct TypefaceKey: EnvironmentKey {
    static let defaultValue = "system"
}

extension EnvironmentValues {
    /// The saved PostScript font name, or a native system design identifier.
    var appTypeface: String {
        get { self[TypefaceKey.self] }
        set { self[TypefaceKey.self] = newValue }
    }
}

/// Resolves semantic text styles without losing Dynamic Type or the requested weight.
enum InterfaceTypography {
    static func font(_ style: Font.TextStyle, typeface: String, weight: Font.Weight? = nil) -> Font {
        if typeface == "system" || typeface == "rounded" {
            return .system(style, design: typeface == "rounded" ? .rounded : .default, weight: weight)
        }
        let size = baselineSize(style)
        guard UIFont(name: typeface, size: size) != nil else { return .system(style, weight: weight) }
        return Font.custom(typeface, size: size, relativeTo: style)
            .weight(weight ?? (style == .headline ? .semibold : .regular))
    }

    static func baselineSize(_ style: Font.TextStyle) -> CGFloat {
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        return UIFont.preferredFont(forTextStyle: uiStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
    }
}

private struct ScaledInterfaceFont: ViewModifier {
    @Environment(\.appTypeface) private var typeface
    @ScaledMetric private var pointSize: CGFloat
    let weight: Font.Weight
    let scale: Double

    init(style: Font.TextStyle, weight: Font.Weight?, scale: Double) {
        _pointSize = ScaledMetric(wrappedValue: InterfaceTypography.baselineSize(style), relativeTo: style)
        self.weight = weight ?? (style == .headline ? .semibold : .regular)
        self.scale = scale
    }

    func body(content: Content) -> some View {
        if typeface == "system" || typeface == "rounded" {
            content.font(.system(size: pointSize * scale, weight: weight, design: typeface == "rounded" ? .rounded : .default))
        } else {
            content.font(.custom(typeface, fixedSize: pointSize * scale).weight(weight))
        }
    }
}

private struct InterfaceFont: ViewModifier {
    @Environment(\.appTypeface) private var typeface
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(InterfaceTypography.font(style, typeface: typeface, weight: weight))
    }
}

extension View {
    /// Uses the selected interface font, retaining the semantic style's accessibility scaling.
    @ViewBuilder
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, scale: Double = 1) -> some View {
        if scale == 1 { modifier(InterfaceFont(style: style, weight: weight)) }
        else { modifier(ScaledInterfaceFont(style: style, weight: weight, scale: scale)) }
    }
}

/// Keeps native large and inline navigation titles in sync with the saved interface face.
/// The system still owns collapse, back navigation, localization and accessibility sizing.
private struct NavigationTitleTypography: ViewModifier {
    let inlineLarge: Bool
    @Environment(\.appTypeface) private var typeface
    @Environment(\.dynamicTypeSize) private var textSize

    func body(content: Content) -> some View {
        content.background {
            NavigationTypefaceBridge(typeface: typeface, textSize: textSize, inlineLarge: inlineLarge)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

/// Updates the containing navigation bar, including its scroll-edge and compact appearances.
/// Per-screen attachment also covers sheets and newly pushed collection detail pages.
private struct NavigationTypefaceBridge: UIViewControllerRepresentable {
    let typeface: String
    let textSize: DynamicTypeSize
    let inlineLarge: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.inlineLarge = inlineLarge
        controller.typeface = typeface
        controller.applyTypeface()
    }

    final class Controller: UIViewController {
        var typeface = "system"
        var inlineLarge = false

        override func loadView() {
            view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyTypeface()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTypeface()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyTypeface()
        }

        /// A disappearing destination must not replace the visible destination's font.
        func applyTypeface() {
            guard let navigationController, let owner = owningDestination(),
                  navigationController.topViewController === owner else { return }
            let bar = navigationController.navigationBar
            let inline = navigationFont(style: inlineLarge ? .largeTitle : .headline, weight: inlineLarge ? .bold : .semibold)
            let large = navigationFont(style: .largeTitle, weight: .bold)
            if bar.titleTextAttributes?[.font] as? UIFont == inline,
               bar.largeTitleTextAttributes?[.font] as? UIFont == large { return }
            var titleAttributes = bar.titleTextAttributes ?? [:]
            var largeAttributes = bar.largeTitleTextAttributes ?? [:]
            titleAttributes[.font] = inline
            largeAttributes[.font] = large
            bar.titleTextAttributes = titleAttributes
            bar.largeTitleTextAttributes = largeAttributes
            bar.standardAppearance = styled(bar.standardAppearance, inline: inline, large: large)
            if let appearance = bar.scrollEdgeAppearance {
                bar.scrollEdgeAppearance = styled(appearance, inline: inline, large: large)
            }
            if let appearance = bar.compactAppearance {
                bar.compactAppearance = styled(appearance, inline: inline, large: large)
            }
            if let appearance = bar.compactScrollEdgeAppearance {
                bar.compactScrollEdgeAppearance = styled(appearance, inline: inline, large: large)
            }
        }

        private func owningDestination() -> UIViewController? {
            var destination: UIViewController = self
            while let parent = destination.parent, !(parent is UINavigationController) {
                destination = parent
            }
            return destination.parent is UINavigationController ? destination : nil
        }

        private func styled(_ source: UINavigationBarAppearance, inline: UIFont, large: UIFont) -> UINavigationBarAppearance {
            let appearance = source.copy() as! UINavigationBarAppearance
            appearance.titleTextAttributes[.font] = inline
            appearance.largeTitleTextAttributes[.font] = large
            return appearance
        }

        private func navigationFont(style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let baseSize = UIFont.preferredFont(forTextStyle: style,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
            let system = UIFont.systemFont(ofSize: baseSize, weight: weight)
            let base: UIFont
            if typeface == "rounded", let descriptor = system.fontDescriptor.withDesign(.rounded) {
                base = UIFont(descriptor: descriptor, size: baseSize)
            } else if typeface != "system", let custom = UIFont(name: typeface, size: baseSize) {
                let descriptor = custom.fontDescriptor.withSymbolicTraits(.traitBold) ?? custom.fontDescriptor
                base = UIFont(descriptor: descriptor, size: baseSize)
            } else {
                base = system
            }
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base, compatibleWith: traitCollection)
        }
    }
}

extension View {
    /// Uses the saved typeface for both native title sizes without replacing navigation chrome.
    func appNavigationTitle(_ title: LocalizedStringKey, inlineLarge: Bool = false) -> some View {
        navigationTitle(title).modifier(NavigationTitleTypography(inlineLarge: inlineLarge))
    }

    /// Dynamic provider and playlist names remain verbatim rather than localization keys.
    @_disfavoredOverload
    func appNavigationTitle<S: StringProtocol>(_ title: S, inlineLarge: Bool = false) -> some View {
        navigationTitle(title).modifier(NavigationTitleTypography(inlineLarge: inlineLarge))
    }
}

/// A registered face may share its file with other weights in a font collection.
struct InterfaceFontFace: Identifiable {
    let id: String
    let title: String
    let importedFile: URL?
}

/// Registers bundled and imported fonts locally; imported font files survive app relaunch.
@MainActor @Observable
final class FontLibrary {
    private(set) var faces: [InterfaceFontFace] = []
    var error: String?
    private let root = URL.applicationSupportDirectory.appendingPathComponent("Fonts", isDirectory: true)
    private static let extensions: Set<String> = ["ttf", "otf", "ttc"]
    private static let maximumBytes = 32 * 1_024 * 1_024

    init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    /// Copies only valid font files from the security-scoped Files selection.
    func importFiles(_ urls: [URL]) {
        error = nil
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                guard Self.extensions.contains(source.pathExtension.lowercased()),
                      let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0, size <= Self.maximumBytes,
                      !descriptors(source).isEmpty else { throw FontImportError.invalid }
                let names = descriptors(source).compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
                if !names.isEmpty && names.allSatisfy({ name in faces.contains { $0.id == name } }) { continue }
                let destination = root.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(source.pathExtension.lowercased())
                try FileManager.default.copyItem(at: source, to: destination)
                var failure: Unmanaged<CFError>?
                guard CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &failure) else {
                    _ = failure?.takeRetainedValue()
                    try? FileManager.default.removeItem(at: destination)
                    throw FontImportError.invalid
                }
            } catch {
                self.error = String(localized: "ios-font-import-error")
            }
        }
        reload()
    }

    /// Removing a collection removes all its faces, and resets a selected face to System.
    func remove(_ face: InterfaceFontFace, settings: SettingsStore) {
        guard let file = face.importedFile else { return }
        do {
            let names = faces.filter { $0.importedFile == file }.map(\.id)
            try FileManager.default.removeItem(at: file)
            CTFontManagerUnregisterFontsForURL(file as CFURL, .process, nil)
            if names.contains(settings.typefaceID) { settings.typefaceID = "system" }
            reload()
        } catch { self.error = String(localized: "ios-font-remove-error") }
    }

    private func reload() {
        let bundled = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Fonts") ?? []
        let imported = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [InterfaceFontFace] = []
        var seen: Set<String> = []
        for file in bundled + imported where Self.extensions.contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            for descriptor in descriptors(file) {
                guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                      seen.insert(name).inserted else { continue }
                let title = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? name
                found.append(InterfaceFontFace(id: name, title: title, importedFile: imported.contains(file) ? file : nil))
            }
        }
        faces = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func descriptors(_ url: URL) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
    }

    private enum FontImportError: Error { case invalid }
}

/// Native font selection, previews and file management in the Appearance settings hierarchy.
struct FontSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(FontLibrary.self) private var fonts
    @State private var showImport = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Picker("ios-interface-font", selection: $settings.typefaceID) {
                    Text("ios-font-system").tag("system")
                    Text("ios-font-rounded").tag("rounded")
                    ForEach(fonts.faces) { face in Text(face.title).tag(face.id) }
                }
                Text("ios-font-preview").appFont(.title2, weight: .semibold)
                Text("ios-font-dynamic-type").appFont(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button("ios-import-fonts", systemImage: "square.and.arrow.down") { showImport = true }
                ForEach(fonts.faces.filter { $0.importedFile != nil }) { face in
                    Text(face.title)
                        .swipeActions {
                            Button("ios-delete", role: .destructive) { fonts.remove(face, settings: settings) }
                        }
                }
                if let error = fonts.error { Text(error).foregroundStyle(.secondary) }
            } footer: { Text("ios-font-import-description") }
        }
        .appNavigationTitle("ios-interface-font")
        .onChange(of: settings.typefaceID, initial: true) { _, _ in recordReview() }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): fonts.importFiles(urls)
            case .failure: fonts.error = String(localized: "ios-font-import-error")
            }
        }
    }

    /// Records registered faces and the selected preference, without exporting a font file.
    private func recordReview() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--sonora-review-url") else { return }
        let selected = settings.typefaceID
        let values: [String: Any] = [
            "selected": selected,
            "persisted": UserDefaults.standard.string(forKey: "sonora.settings.typefaceID") ?? "system",
            "registered_faces": fonts.faces.count,
            "selected_available": selected == "system" || selected == "rounded" || UIFont(name: selected, size: UIFont.systemFontSize) != nil,
            "rounded_available": UIFont.systemFont(ofSize: UIFont.systemFontSize).fontDescriptor.withDesign(.rounded) != nil
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values) {
            try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("font-review.json"), options: .atomic)
        }
        #endif
    }
}
