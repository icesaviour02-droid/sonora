import SwiftUI
import UniformTypeIdentifiers

/// Native source controls and word timing share the desktop parser's line/word/lane data.
struct LyricsContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: LyricsStore
    let retry: () -> Void
    @State private var showSources = false
    @State private var showImport = false
    @State private var followsPlayback = true

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            options
            if store.isLoading && store.sheet == nil {
                ProgressView("ios-loading-lyrics").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.error {
                ContentUnavailableView {
                    Label("ios-lyrics-unavailable", systemImage: "quote.bubble")
                } description: { Text(error) } actions: { Button("ios-retry", action: retry).buttonStyle(.glass) }
            } else if store.sheet?.instrumental == true {
                ContentUnavailableView("ios-lyrics-instrumental", systemImage: "music.quarternote.3")
            } else if settings.syncedLyrics, store.sheet?.synced == true, let lines = store.sheet?.lines, !lines.isEmpty {
                TimelineView(.animation(minimumInterval: 0.1, paused: !playback.isPlaying)) { _ in
                    synced(lines, at: playback.presentationElapsed)
                }
            } else if let text = store.sheet?.text, !text.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.spacing) {
                        Text(text).appFont(.title3, weight: .semibold, scale: settings.lyricsScale)
                            .foregroundStyle(.white.opacity(0.92))
                        if settings.romanizedLyrics, let romanized = store.sheet?.romanized {
                            Text(romanized).appFont(.subheadline, scale: settings.lyricsScale).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Layout.compact)
                }
            } else {
                ContentUnavailableView("ios-lyrics-unavailable", systemImage: "quote.bubble", description: Text("ios-no-lyrics-description"))
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showSources) {
            NavigationStack {
                LyricsSourcesSettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("ios-done") { showSources = false } }
                }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.plainText, .xml, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, let track = playback.current { store.importFile(url, trackID: track.id) }
            case .failure: store.error = String(localized: "ios-lyrics-import-error")
            }
        }
        .onChange(of: playback.current?.id) { _, _ in followsPlayback = true }
    }

    private var options: some View {
        HStack {
            if let source = store.sheet?.source {
                Text(source).appFont(.caption).foregroundStyle(.white.opacity(0.7))
            }
            if store.usingSaved { Image(systemName: "arrow.down.circle").accessibilityLabel(Text("ios-saved-lyrics")) }
            Spacer()
            Menu {
                ForEach(Array(store.available.enumerated()), id: \.offset) { index, choice in
                    if let source = choice.source {
                        Button { followsPlayback = true; store.select(index) } label: {
                            Label {
                                Text(source)
                                Text(choice.worded == true ? "ios-lyrics-word-timing" : (choice.synced == true ? "ios-lyrics-synced-format" : "ios-lyrics-plain-format"))
                            } icon: { Image(systemName: store.selected == index ? "checkmark" : "quote.bubble") }
                        }
                    }
                }
                Button("ios-lyrics-sources", systemImage: "slider.horizontal.3") { showSources = true }
                Button("ios-import-lyrics", systemImage: "square.and.arrow.down") { showImport = true }
                    .disabled(settings.lyricsSources.first { $0.source == .local }?.enabled != true)
                Button("ios-copy-lyrics", systemImage: "doc.on.doc") { UIPasteboard.general.string = store.sheet?.text }
                    .disabled(store.sheet?.hasContent != true)
                Button("ios-refresh-lyrics", systemImage: "arrow.clockwise", action: retry)
            } label: {
                Image(systemName: "ellipsis").frame(minWidth: Layout.control, minHeight: Layout.control)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("ios-lyrics-options"))
        }
    }

    private func synced(_ lines: [LyricsLineItem], at elapsed: Double) -> some View {
        let active = lines.last { ($0.start_seconds ?? .infinity) <= elapsed }?.id ?? lines.first?.id
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Layout.spacing) {
                    ForEach(lines) { line in
                        Button {
                            if let start = line.start_seconds {
                                playback.seek(to: start)
                                if !playback.isPlaying { playback.resume() }
                            }
                        } label: {
                            LyricsLineView(line: line, active: line.id == active)
                        }
                        .buttonStyle(.plain).id(line.id)
                    }
                    if let writers = store.sheet?.writers, !writers.isEmpty {
                        Text(writers.joined(separator: ", ")).appFont(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.vertical, Layout.spacing)
            }
            .onScrollPhaseChange { _, phase, _ in
                if phase == .interacting { followsPlayback = false }
            }
            .onChange(of: active, initial: true) { _, id in
                guard followsPlayback, let id else { return }
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsPlayback, let active {
                    Button("ios-follow-lyrics", systemImage: "location.fill") {
                        followsPlayback = true
                        withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(active, anchor: .center) }
                    }
                    .buttonStyle(.glass).padding(Layout.compact)
                }
            }
        }
    }
}

private struct LyricsLineView: View {
    @Environment(SettingsStore.self) private var settings
    let line: LyricsLineItem
    let active: Bool
    private var counter: Bool { line.voice == "counter" }

    var body: some View {
        VStack(alignment: counter ? .trailing : .leading, spacing: Layout.compact / 2) {
            LyricsTimedText(text: line.text, words: line.words ?? [], active: active)
                .appFont(active ? .title2 : .title3, weight: .bold, scale: settings.lyricsScale)
            if settings.romanizedLyrics, let text = line.romanized {
                Text(text).appFont(.subheadline, weight: .medium, scale: settings.lyricsScale)
                    .foregroundStyle(.white.opacity(active ? 0.8 : 0.4))
            }
            if settings.backingVocals {
                ForEach(line.secondary ?? []) { lane in
                    LyricsTimedText(text: lane.text, words: lane.words ?? [], active: active)
                        .appFont(.subheadline, weight: .semibold, scale: settings.lyricsScale)
                }
            }
        }
        .multilineTextAlignment(counter ? .trailing : .leading)
        .frame(maxWidth: .infinity, minHeight: Layout.control, alignment: counter ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .blur(radius: !active && settings.blurInactiveLyrics ? 1.2 : 0)
    }
}

/// One attributed paragraph wraps naturally; only the active line updates word progress at 30 Hz.
private struct LyricsTimedText: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackController.self) private var playback
    let text: String
    let words: [LyricsWordItem]
    let active: Bool

    var body: some View {
        if active && settings.karaokeLyrics && !words.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
                Text(highlight(at: playback.presentationElapsed))
            }
        } else { Text(text).foregroundStyle(.white.opacity(active ? 1 : 0.42)) }
    }

    private func highlight(at now: Double) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .white.opacity(0.4)
        var cursor = text.startIndex
        for word in words {
            let token = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, let range = text.range(of: token, range: cursor..<text.endIndex),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            let progress = min(max((now - word.start_seconds) / max(word.end_seconds - word.start_seconds, 0.01), 0), 1)
            result[start..<end].foregroundColor = .white.opacity(0.4 + 0.6 * progress)
            cursor = range.upperBound
        }
        return result
    }
}

/// Priority affects ties between timing qualities, matching the desktop's ranking rules.
struct LyricsSourcesSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                ForEach($settings.lyricsSources) { $preference in
                    Toggle(preference.source.label, isOn: $preference.enabled)
                }
                .onMove { settings.lyricsSources.move(fromOffsets: $0, toOffset: $1) }
            } footer: { Text("ios-lyrics-priority-description") }
        }
        .navigationTitle("ios-lyrics-sources")
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
    }
}
