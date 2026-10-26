import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The desktop's supported parametric filter types and their native settings labels.
enum SoundFilterKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case peak, lowShelf = "low-shelf", highShelf = "high-shelf", lowPass = "low-pass"
    case highPass = "high-pass", notch, bandPass = "band-pass", allPass = "all-pass"
    var id: String { rawValue }
    var hasGain: Bool { self == .peak || self == .lowShelf || self == .highShelf }
    var isShelf: Bool { self == .lowShelf || self == .highShelf }
    var label: LocalizedStringKey {
        switch self {
        case .peak: "ios-filter-peak"
        case .lowShelf: "ios-filter-low-shelf"
        case .highShelf: "ios-filter-high-shelf"
        case .lowPass: "ios-filter-low-pass"
        case .highPass: "ios-filter-high-pass"
        case .notch: "ios-filter-notch"
        case .bandPass: "ios-filter-band-pass"
        case .allPass: "ios-filter-all-pass"
        }
    }
}

enum SoundWidthUnit: String, Codable, CaseIterable, Identifiable, Hashable {
    case q, octaves
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .q ? "ios-filter-q" : "ios-filter-octaves" }
}

/// UI identity stays local; only validated numeric filter fields are sent to the core.
struct SoundFilter: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: SoundFilterKind = .peak
    var frequency: Double = 1_000
    var gain: Double = 0
    var widthUnit: SoundWidthUnit = .q
    var width: Double = 0.707
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey { case id, kind, frequency, gain, widthUnit = "width_unit", width, enabled }

    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try values.decode(SoundFilterKind.self, forKey: .kind)
        frequency = try values.decode(Double.self, forKey: .frequency)
        gain = try values.decode(Double.self, forKey: .gain)
        widthUnit = try values.decode(SoundWidthUnit.self, forKey: .widthUnit)
        width = try values.decode(Double.self, forKey: .width)
        enabled = try values.decode(Bool.self, forKey: .enabled)
    }

    var payload: [String: Any] {
        ["kind": kind.rawValue, "frequency": frequency, "gain": gain,
         "width_unit": widthUnit.rawValue, "width": width, "enabled": enabled]
    }
}

struct SoundProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var filters: [SoundFilter]
    var autoPreamp: Bool
    var preampDB: Double
}

/// Validates edits/imports with the desktop parser and commits the profile file atomically.
@MainActor @Observable
final class SoundProfileStore {
    private(set) var profiles: [SoundProfile] = []
    private(set) var selectedID: String
    private(set) var revision = 0
    private(set) var isBusy = false
    private(set) var skippedLines: [Int] = []
    private(set) var isWritable = true
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    #if DEBUG
    @ObservationIgnored private var reviewTask: Task<Void, Never>?
    #endif
    private let file = URL.applicationSupportDirectory.appendingPathComponent("State/sound-profiles.json")

    private struct Saved: Codable { let version: Int; let profiles: [SoundProfile] }
    var selected: SoundProfile? { profiles.first { $0.id.uuidString == selectedID } }

    init() {
        selectedID = UserDefaults.standard.string(forKey: "sonora.settings.soundProfile") ?? ""
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                profiles = saved.profiles
            } catch {
                isWritable = false
                self.error = String(localized: "ios-sound-profiles-load-error")
            }
        }
        if selected == nil { selectedID = "" }
    }

    func select(_ profile: SoundProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        selectedID = profile.id.uuidString
        UserDefaults.standard.set(selectedID, forKey: "sonora.settings.soundProfile")
        revision += 1
    }

    func create(name: String, preset: EqualizerPreset, selected: @escaping () -> Void) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !name.isEmpty else { error = String(localized: "ios-sound-profile-name-error"); return }
        run {
            let description = try await NativeProvider.describeEqualizer(["operation": "equalizer_describe", "preset": preset.coreID])
            try Task.checkCancellation()
            let profile = SoundProfile(name: name, filters: description.filters,
                autoPreamp: description.auto_preamp, preampDB: description.preamp_db)
            try self.commit(self.profiles + [profile])
            self.select(profile)
            selected()
        }
    }

    /// A draft is never applied or saved until the core accepts every filter and preamp value.
    func save(_ draft: SoundProfile, completed: @escaping () -> Void) {
        let name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !name.isEmpty else { error = String(localized: "ios-sound-profile-name-error"); return }
        run {
            let description = try await NativeProvider.describeEqualizer(self.payload(for: draft))
            try Task.checkCancellation()
            var updated = draft
            updated.name = name
            updated.filters = zip(description.filters, draft.filters).map { normalized, original in
                var filter = normalized
                filter.id = original.id
                return filter
            }
            var next = self.profiles
            guard let index = next.firstIndex(where: { $0.id == draft.id }) else { return }
            next[index] = updated
            try self.commit(next)
            completed()
        }
    }

    func remove(_ profile: SoundProfile) {
        do {
            try commit(profiles.filter { $0.id != profile.id })
            if selectedID == profile.id.uuidString {
                selectedID = ""
                UserDefaults.standard.removeObject(forKey: "sonora.settings.soundProfile")
                revision += 1
            }
        } catch { self.error = String(localized: "ios-sound-profile-save-error") }
    }

    func importFile(_ source: URL, selected: @escaping () -> Void) {
        run {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= 1_024 * 1_024 else { throw ProviderError.equalizerInvalid }
            let text = try String(contentsOf: source, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderError.equalizerInvalid }
            let description = try await NativeProvider.describeEqualizer([
                "operation": "equalizer_describe", "preset": "flat", "profile": text
            ])
            try Task.checkCancellation()
            let profile = SoundProfile(name: String(source.deletingPathExtension().lastPathComponent.prefix(200)),
                filters: description.filters, autoPreamp: description.auto_preamp, preampDB: description.preamp_db)
            try self.commit(self.profiles + [profile])
            self.skippedLines = description.skipped_lines
            self.select(profile)
            selected()
        }
    }

    func export(_ profile: SoundProfile, completed: @escaping (String) -> Void) {
        run {
            let description = try await NativeProvider.describeEqualizer(self.payload(for: profile))
            try Task.checkCancellation()
            completed(description.profile)
        }
    }

    private func payload(for profile: SoundProfile) -> [String: Any] {
        ["operation": "equalizer_describe", "preset": "flat", "filters": profile.filters.map(\.payload),
         "auto_preamp": profile.autoPreamp, "preamp_db": profile.preampDB]
    }

    private func commit(_ next: [SoundProfile]) throws {
        guard isWritable else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Saved(version: 1, profiles: next)).write(to: file, options: .atomic)
        profiles = next
        revision += 1
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard isWritable else { return }
        task?.cancel()
        let generation = UUID()
        self.generation = generation
        isBusy = true
        error = nil
        skippedLines = []
        task = Task { [weak self] in
            do { try await work() }
            catch is CancellationError {}
            catch {
                if self?.generation == generation {
                    self?.error = (error as? ProviderError)?.errorDescription ?? String(localized: "ios-sound-profile-save-error")
                }
            }
            if self?.generation == generation { self?.isBusy = false }
        }
    }

    #if DEBUG
    /// Exercises create/edit/export/import/restore/delete through the same store used by the UI.
    func review(completed: @escaping () -> Void) {
        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self else { return }
            let before = Set(self.profiles.map(\.id))
            var checks: [String: Bool] = [:]
            var finished = false
            defer {
                let values: [String: Any] = ["passed": finished && checks.values.allSatisfy { $0 }, "checks": checks]
                if let data = try? JSONSerialization.data(withJSONObject: values) {
                    try? data.write(to: URL.applicationSupportDirectory.appendingPathComponent("sound-profiles-review.json"), options: .atomic)
                }
            }
            self.create(name: "Sonora Sound Review", preset: .bassBoost, selected: {})
            guard await self.waitForOperation(), var profile = self.profiles.first(where: { !before.contains($0.id) }) else { return }
            checks["create_preset_profile"] = profile.filters.count == 10 && profile.autoPreamp
            profile.name = "Sonora Edited Sound Review"
            profile.filters[0].kind = .notch
            profile.filters[0].frequency = 1_000
            profile.filters.append(SoundFilter())
            self.save(profile, completed: {})
            guard await self.waitForOperation(), let edited = self.profiles.first(where: { $0.id == profile.id }) else { return }
            checks["edit_validate_save"] = edited.name == profile.name && edited.filters.count == 11 && edited.filters[0].gain == 0
            var text = ""
            self.export(edited) { text = $0 }
            guard await self.waitForOperation(), !text.isEmpty else { return }
            checks["export_profile"] = true
            let source = URL.cachesDirectory.appendingPathComponent("sonora-imported-sound-review.txt")
            do { try (text + "\nChannel: L\n").write(to: source, atomically: true, encoding: .utf8) }
            catch { return }
            self.importFile(source, selected: {})
            guard await self.waitForOperation(), let imported = self.selected, imported.id != edited.id else { return }
            checks["import_profile"] = imported.filters.count == edited.filters.count
            checks["report_unsupported_lines"] = !self.skippedLines.isEmpty
            let reloaded = SoundProfileStore()
            checks["restore_profiles_selection"] = reloaded.selectedID == self.selectedID && reloaded.profiles.count == before.count + 2
            self.remove(imported)
            checks["delete_one_profile"] = self.profiles.count == before.count + 1 && !self.profiles.contains { $0.id == imported.id }
            self.select(edited)
            finished = true
            completed()
        }
    }

    private func waitForOperation() async -> Bool {
        for _ in 0..<600 {
            if Task.isCancelled { return false }
            if !isBusy { return error == nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
    #endif
}

/// Equalizer APO text can be shared through the system Files exporter.
struct SoundProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
