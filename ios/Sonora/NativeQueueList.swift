import SwiftUI
import UIKit

/// UIKit owns row lifting, auto-scroll, cancellation and swipe actions. Playback owns every edit.
struct NativeQueueList: UIViewRepresentable {
    @Environment(\.appTypeface) private var typeface
    let upcoming: [QueuedTrack]
    let history: [MusicTrack]
    let autoplay: Bool
    let playback: PlaybackController
    let settings: SettingsStore
    let addSongs: () -> Void

    init(upcoming: [QueuedTrack], history: [MusicTrack], autoplay: Bool, playback: PlaybackController,
         settings: SettingsStore, addSongs: @escaping () -> Void) {
        self.upcoming = upcoming; self.history = history; self.autoplay = autoplay
        self.playback = playback; self.settings = settings; self.addSongs = addSongs
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UICollectionView { context.coordinator.makeCollection() }
    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh()
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate {
        enum Entry: Hashable, Sendable {
            case historyHeader, past(Int), queueHeader, song(UUID), add, autoplay
        }
        var parent: NativeQueueList
        private weak var collection: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, Entry>!
        private var tracks: [Entry: MusicTrack] = [:]
        private var didPositionQueue = false
        private var lastTypeface: String?

        init(parent: NativeQueueList) { self.parent = parent }

        func makeCollection() -> UICollectionView {
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.backgroundColor = .clear
            configuration.showsSeparators = false
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] index in self?.swipeActions(at: index) }
            let view = QueueCollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
            view.backgroundColor = .clear
            view.overrideUserInterfaceStyle = .dark
            view.contentInsetAdjustmentBehavior = .never
            view.delegate = self
            view.dragInteractionEnabled = true
            collection = view
            view.layoutReady = { [weak self] in self?.positionQueue() }
            let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Entry> { [weak self] cell, _, entry in
                guard let self else { return }
                cell.backgroundConfiguration = .clear()
                cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                    if let self { self.row(entry).environment(self.parent.settings).environment(\.appTypeface, self.parent.typeface) }
                }.margins(.all, 0)
                if case .song = entry { cell.accessories = [.reorder(displayed: .always)] }
                else { cell.accessories = [] }
            }
            dataSource = UICollectionViewDiffableDataSource<Int, Entry>(collectionView: view) { collection, index, entry in
                collection.dequeueConfiguredReusableCell(using: registration, for: index, item: entry)
            }
            dataSource.reorderingHandlers.canReorderItem = { entry in
                if case .song = entry { return true }
                return false
            }
            dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
                guard let self else { return }
                let order = transaction.finalSnapshot.itemIdentifiers.compactMap { entry -> UUID? in
                    guard case .song(let id) = entry else { return nil }
                    return id
                }
                self.parent.playback.reorderUpcoming(order)
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            refresh()
            return view
        }

        /// The same identifiers drive native animations and persisted queue occurrences.
        func refresh() {
            guard let collection, dataSource != nil, !collection.hasActiveDrag, !collection.hasActiveDrop else { return }
            let upcoming = parent.playback.upcomingItems
            let history = Array(parent.settings.history.reversed())
            var entries: [Entry] = []
            var updated: [Entry: MusicTrack] = [:]
            if !history.isEmpty {
                entries.append(.historyHeader)
                for (index, track) in history.enumerated() { entries.append(.past(index)); updated[.past(index)] = track }
            }
            entries.append(.queueHeader)
            for item in upcoming { entries.append(.song(item.id)); updated[.song(item.id)] = item.track }
            entries.append(.add)
            if parent.settings.autoplayRadio { entries.append(.autoplay) }
            let old = dataSource.snapshot()
            let changes = entries.filter { updated[$0] != tracks[$0] }
            let fontChanged = lastTypeface != parent.typeface
            lastTypeface = parent.typeface
            tracks = updated
            if old.itemIdentifiers == entries && changes.isEmpty && !fontChanged { return }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Entry>()
            snapshot.appendSections([0])
            snapshot.appendItems(entries)
            // Headers have changing disabled states, independent of the song metadata.
            let reconfigure = Set(fontChanged ? entries : changes).union([.queueHeader, .historyHeader])
            snapshot.reconfigureItems(entries.filter { reconfigure.contains($0) && old.indexOfItem($0) != nil })
            dataSource.apply(snapshot, animatingDifferences: didPositionQueue && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                self?.positionQueue()
            }
        }

        private func positionQueue() {
            guard let collection, collection.bounds.width > 0, collection.bounds.height > 0,
                  let index = dataSource?.indexPath(for: .queueHeader),
                  let attributes = collection.layoutAttributesForItem(at: index) else { return }
            let tail = collection.contentSize.height - attributes.frame.minY
            let padding = max(0, collection.bounds.height - tail)
            if collection.contentInset.bottom != padding { collection.contentInset.bottom = padding }
            if !didPositionQueue {
                didPositionQueue = true
                collection.scrollToItem(at: index, at: .top, animated: false)
            }
        }

        /// History, headers and Add Songs never become destinations for an upcoming song.
        func collectionView(_ collectionView: UICollectionView,
                            targetIndexPathForMoveOfItemFromOriginalIndexPath original: IndexPath,
                            atCurrentIndexPath current: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
            let items = dataSource.snapshot().itemIdentifiers
            let positions = items.indices.filter { if case .song = items[$0] { return true }; return false }
            guard let first = positions.first, let last = positions.last else { return current }
            return IndexPath(item: min(max(proposed.item, first), last), section: 0)
        }

        private func swipeActions(at index: IndexPath) -> UISwipeActionsConfiguration? {
            guard let entry = dataSource.itemIdentifier(for: index) else { return nil }
            let title: String
            switch entry {
            case .song: title = String(localized: "ios-remove-from-queue")
            case .past: title = String(localized: "ios-delete")
            default: return nil
            }
            let action = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, complete in
                guard let self else { complete(false); return }
                switch entry {
                case .song(let id): self.parent.playback.removeQueueItem(id)
                case .past: if let track = self.tracks[entry] { self.parent.settings.removeFromHistory(track) }
                default: complete(false); return
                }
                self.refresh()
                complete(true)
            }
            return UISwipeActionsConfiguration(actions: [action])
        }

        @ViewBuilder private func row(_ entry: Entry) -> some View {
            switch entry {
            case .song(let id):
                if let track = tracks[entry] {
                    Button { [weak self] in self?.parent.playback.selectQueueItem(id) } label: { QueueSongLabel(track: track) }
                        .buttonStyle(.plain).accessibilityIdentifier("queue-row-" + id.uuidString)
                }
            case .past:
                if let track = tracks[entry] {
                    Button { [weak self] in
                        guard let self else { return }
                        self.parent.playback.play(track, in: self.parent.settings.history)
                    } label: { QueueSongLabel(track: track) }.buttonStyle(.plain)
                }
            case .queueHeader:
                header("ios-queue", identifier: "queue-clear", disabled: parent.playback.upcomingItems.isEmpty) { [weak self] in self?.parent.playback.clearUpcomingQueue() }
            case .historyHeader:
                header("ios-history", identifier: "queue-clear-history", disabled: parent.settings.history.isEmpty) { [weak self] in self?.parent.settings.clearHistory() }
            case .add:
                Button { [weak self] in self?.parent.addSongs() } label: {
                    HStack(spacing: Layout.compact) {
                        Image(systemName: "plus").appFont(.title2)
                            .frame(width: Layout.rowArtwork, height: Layout.rowArtwork)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Layout.compact))
                        Text("ios-add-songs-to-queue").appFont(.body)
                        Spacer(minLength: 0)
                    }.foregroundStyle(.white).padding(.vertical, Layout.compact / 2)
                }.buttonStyle(.plain).accessibilityIdentifier("queue-add-songs")
            case .autoplay:
                VStack(alignment: .leading, spacing: Layout.compact / 2) {
                    Label("ios-autoplay-radio", systemImage: "infinity").appFont(.headline)
                    Text("ios-autoplay-description").appFont(.subheadline).foregroundStyle(.white.opacity(0.65))
                }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Layout.spacing)
            }
        }

        private func header(_ title: LocalizedStringKey, identifier: String, disabled: Bool, action: @escaping () -> Void) -> some View {
            HStack {
                Text(title).appFont(.headline)
                Spacer()
                Button("ios-clear", action: action).appFont(.subheadline)
                    .frame(minHeight: Layout.control).disabled(disabled).accessibilityIdentifier(identifier)
            }.foregroundStyle(.white).padding(.vertical, Layout.compact / 2)
        }
    }
}

/// Initial queue positioning waits for the real player viewport rather than a zero-size makeUIView.
private final class QueueCollectionView: UICollectionView {
    var layoutReady: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); layoutReady?() }
}

/// The native queue and its drag preview use the same artwork and text metrics as other song rows.
private struct QueueSongLabel: View {
    let track: MusicTrack
    var body: some View {
        HStack(spacing: Layout.compact) {
            ArtworkView(track: track, side: Layout.rowArtwork).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(track.title).appFont(.subheadline, weight: .medium).foregroundStyle(.white).lineLimit(1)
                Text(track.artist).appFont(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            }
            Spacer(minLength: Layout.compact)
        }
        .padding(.vertical, Layout.compact / 2)
        .frame(maxWidth: .infinity, minHeight: Layout.control, alignment: .leading).contentShape(Rectangle())
    }
}
