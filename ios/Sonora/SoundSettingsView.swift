import SwiftUI
import UniformTypeIdentifiers

/// Groups everyday sound controls and advanced profiles into native settings pages.
struct SoundSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("ios-equalizer-enable", isOn: $settings.equalizerEnabled)
                    .onChange(of: settings.equalizerEnabled) { _, _ in playback.applyAudioGain() }
                Picker("ios-equalizer-preset", selection: $settings.equalizerPreset) {
                    ForEach(EqualizerPreset.allCases) { preset in Text(preset.labelKey).tag(preset) }
                }
                .onChange(of: settings.equalizerPreset) { _, _ in playback.applyAudioGain() }
                if settings.equalizerPreset == .custom {
                    Picker("ios-sound-profile", selection: Binding(
                        get: { settings.soundProfiles.selectedID },
                        set: { id in
                            if let profile = settings.soundProfiles.profiles.first(where: { $0.id.uuidString == id }) {
                                settings.soundProfiles.select(profile)
                            }
                        }
                    )) {
                        Text("ios-sound-no-profile").tag("")
                        ForEach(settings.soundProfiles.profiles) { profile in Text(profile.name).tag(profile.id.uuidString) }
                    }
                }
                NavigationLink("ios-sound-profiles") { SoundProfilesView() }
            }
            Section("ios-equalizer-preamp") {
                if settings.equalizerPreset == .custom, let profile = settings.soundProfiles.selected {
                    NavigationLink(profile.name) { SoundProfileEditor(profile: profile) }
                    Text("ios-sound-profile-preamp-description").foregroundStyle(.secondary)
                } else {
                    Toggle("ios-equalizer-auto-preamp", isOn: $settings.autoPreamp)
                        .onChange(of: settings.autoPreamp) { _, _ in playback.applyAudioGain() }
                    DecibelControl(title: "ios-equalizer-preamp", value: $settings.preampDB, range: -30...12)
                        .disabled(settings.autoPreamp)
                        .onChange(of: settings.preampDB) { _, _ in playback.applyAudioGain() }
                }
                LabeledContent("ios-equalizer-effective-preamp", value: String(format: "%+.1f dB", playback.audioEffects.preampDB))
            }
            Section("ios-tone-controls") {
                DecibelControl(title: "ios-equalizer-bass", value: $settings.bassDB, range: -12...12)
                    .onChange(of: settings.bassDB) { _, _ in playback.applyAudioGain() }
                DecibelControl(title: "ios-equalizer-treble", value: $settings.trebleDB, range: -12...12)
                    .onChange(of: settings.trebleDB) { _, _ in playback.applyAudioGain() }
                Button("ios-equalizer-reset") { settings.resetEqualizer(); playback.applyAudioGain() }
            }
            if let error = playback.audioEffects.error {
                Section { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("ios-equalizer")
    }
}

/// A semantic slider row reused by sound settings and individual filter editors.
private struct DecibelControl: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            LabeledContent(title) { Text(String(format: "%+.1f dB", value)).appFont(.caption).monospacedDigit() }
            Slider(value: $value, in: range, step: 0.5).accessibilityLabel(Text(title))
        }
    }
}

struct SoundProfilesView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var showCreate = false
    @State private var showImport = false
    @State private var showExport = false
    @State private var document: SoundProfileDocument?
    @State private var exportName = ""
    @State private var deleting: SoundProfile?

    var body: some View {
        let store = settings.soundProfiles
        List {
            Section {
                Button("ios-sound-profile-create", systemImage: "plus") { showCreate = true }
                Button("ios-sound-profile-import", systemImage: "square.and.arrow.down") { showImport = true }
            }
            .disabled(store.isBusy || !store.isWritable)
            Section {
                ForEach(store.profiles) { profile in
                    NavigationLink { SoundProfileEditor(profile: profile) } label: {
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if store.selectedID == profile.id.uuidString && settings.equalizerPreset == .custom {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .contextMenu {
                        Button("ios-sound-profile-use", systemImage: "checkmark") {
                            settings.equalizerPreset = .custom
                            store.select(profile)
                        }
                        Button("ios-sound-profile-export", systemImage: "square.and.arrow.up") { export(profile) }
                        Button("ios-delete", role: .destructive) { deleting = profile }
                    }
                    .swipeActions { Button("ios-delete", role: .destructive) { deleting = profile } }
                }
                if store.profiles.isEmpty { Text("ios-sound-profiles-empty").foregroundStyle(.secondary) }
            } footer: { Text("ios-sound-profiles-description") }
            if !store.skippedLines.isEmpty {
                Section {
                    LabeledContent("ios-sound-profile-skipped", value: store.skippedLines.map(String.init).joined(separator: ", "))
                    Text("ios-sound-profile-skipped-description").foregroundStyle(.secondary)
                }
            }
            if let error = store.error { Section { Text(error).foregroundStyle(.secondary) } }
            if store.isBusy { ProgressView() }
        }
        .navigationTitle("ios-sound-profiles")
        .sheet(isPresented: $showCreate) { NavigationStack { CreateSoundProfileView() } }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.importFile(url) { settings.equalizerPreset = .custom } }
            case .failure: store.error = String(localized: "ios-sound-profile-import-error")
            }
        }
        .fileExporter(isPresented: $showExport, document: document, contentType: .plainText, defaultFilename: exportName) { result in
            if case .failure = result { store.error = String(localized: "ios-sound-profile-export-error") }
        }
        .confirmationDialog("ios-sound-profile-delete", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("ios-delete", role: .destructive) { if let deleting { store.remove(deleting) }; deleting = nil }
            Button("ios-cancel", role: .cancel) { deleting = nil }
        }
    }

    private func export(_ profile: SoundProfile) {
        settings.soundProfiles.export(profile) { text in
            document = SoundProfileDocument(text: text)
            exportName = String(profile.name.prefix(60)).replacingOccurrences(of: "/", with: "-")
            showExport = true
        }
    }
}

private struct CreateSoundProfileView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var preset: EqualizerPreset = .flat

    var body: some View {
        Form {
            TextField("ios-sound-profile-name", text: $name)
            Picker("ios-sound-profile-starting-preset", selection: $preset) {
                ForEach(EqualizerPreset.allCases.filter { $0 != .custom }) { preset in Text(preset.labelKey).tag(preset) }
            }
            if let error = settings.soundProfiles.error { Text(error).foregroundStyle(.secondary) }
        }
        .navigationTitle("ios-sound-profile-create")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-create") {
                    settings.soundProfiles.create(name: name, preset: preset) {
                        settings.equalizerPreset = .custom
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.soundProfiles.isBusy)
            }
        }
    }
}

/// All eight filter types, their widths, preamp and order use the desktop core's validation.
struct SoundProfileEditor: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SoundProfile
    @State private var editing: SoundFilter?

    init(profile: SoundProfile) { _draft = State(initialValue: profile) }

    var body: some View {
        Form {
            Section { SoundResponseView(profile: draft) }
            Section {
                TextField("ios-sound-profile-name", text: $draft.name)
                Toggle("ios-equalizer-auto-preamp", isOn: $draft.autoPreamp)
                DecibelControl(title: "ios-equalizer-preamp", value: $draft.preampDB, range: -30...12)
                    .disabled(draft.autoPreamp)
            }
            Section {
                ForEach(draft.filters) { filter in
                    Button { editing = filter } label: {
                        VStack(alignment: .leading, spacing: Layout.compact / 2) {
                            HStack {
                                Text(filter.kind.label).foregroundStyle(.primary)
                                Spacer()
                                if !filter.enabled { Text("ios-filter-disabled").foregroundStyle(.secondary) }
                            }
                            HStack {
                                Text(filter.frequency, format: .number.precision(.fractionLength(0...2)))
                                Text("ios-unit-hertz")
                                if filter.kind.hasGain { Text(String(format: "%+.1f dB", filter.gain)) }
                            }
                            .appFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { draft.filters.remove(atOffsets: $0) }
                .onMove { draft.filters.move(fromOffsets: $0, toOffset: $1) }
                Button("ios-filter-add", systemImage: "plus") { editing = SoundFilter() }
                    .disabled(draft.filters.count >= 20)
            } header: { Text("ios-sound-filters") } footer: { Text("ios-sound-filters-description") }
            if let error = settings.soundProfiles.error { Section { Text(error).foregroundStyle(.secondary) } }
        }
        .navigationTitle(draft.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-save") { settings.soundProfiles.save(draft) { dismiss() } }
                    .disabled(settings.soundProfiles.isBusy || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(item: $editing) { filter in
            NavigationStack {
                SoundFilterEditor(filter: filter) { changed in
                    if let index = draft.filters.firstIndex(where: { $0.id == changed.id }) { draft.filters[index] = changed }
                    else if draft.filters.count < 20 { draft.filters.append(changed) }
                }
            }
        }
    }
}

private struct SoundFilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: SoundFilter
    let saved: (SoundFilter) -> Void

    init(filter: SoundFilter, saved: @escaping (SoundFilter) -> Void) {
        _filter = State(initialValue: filter)
        self.saved = saved
    }

    var body: some View {
        Form {
            Toggle("ios-filter-enabled", isOn: $filter.enabled)
            Picker("ios-filter-type", selection: $filter.kind) {
                ForEach(SoundFilterKind.allCases) { kind in Text(kind.label).tag(kind) }
            }
            .onChange(of: filter.kind) { _, kind in
                if kind.isShelf && filter.widthUnit == .octaves { filter.widthUnit = .q; filter.width = 0.707 }
                if !kind.hasGain { filter.gain = 0 }
            }
            LabeledContent("ios-filter-frequency") {
                TextField("ios-filter-frequency", value: $filter.frequency, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            if filter.kind.hasGain { DecibelControl(title: "ios-filter-gain", value: $filter.gain, range: -24...24) }
            if !filter.kind.isShelf { widthPicker }
            widthControl
        }
        .navigationTitle("ios-sound-filter")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("ios-cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ios-done") { saved(filter); dismiss() }
                    .disabled(!filter.frequency.isFinite || !(10...24_000).contains(filter.frequency))
            }
        }
    }

    private var widthRange: ClosedRange<Double> {
        filter.widthUnit == .q ? 0.05...50.0 : 0.01...6.0
    }

    private var widthPicker: some View {
        Picker("ios-filter-width-unit", selection: $filter.widthUnit) {
            ForEach(SoundWidthUnit.allCases) { unit in Text(unit.label).tag(unit) }
        }
        .onChange(of: filter.widthUnit) { _, _ in
            filter.width = min(max(filter.width, widthRange.lowerBound), widthRange.upperBound)
        }
    }

    private var widthControl: some View {
        Stepper(value: $filter.width, in: widthRange, step: 0.01) {
            LabeledContent(filter.widthUnit.label) {
                Text(filter.width, format: .number.precision(.fractionLength(0...3)))
            }
        }
    }
}
