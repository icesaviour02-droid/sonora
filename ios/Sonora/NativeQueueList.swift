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
    let headerRevision: Int
    let headerView: AnyView
    let headerHeight: CGFloat
    let historyHeaderBottom: (CGFloat) -> Void
    let headerOffset: (CGFloat) -> Void

    init(upcoming: [QueuedTrack], history: [MusicTrack], autoplay: Bool, playback: PlaybackController,
         settings: SettingsStore, headerRevision: Int, headerView: AnyView, headerHeight: CGFloat, historyHeaderBottom: @escaping (CGFloat) -> Void, headerOffset: @escaping (CGFloat) -> Void,
         addSongs: @escaping () -> Void) {
        self.upcoming = upcoming; self.history = history; self.autoplay = autoplay
        self.playback = playback; self.settings = settings; self.addSongs = addSongs
        self.headerRevision = headerRevision; self.headerView = headerView; self.headerHeight = headerHeight; self.historyHeaderBottom = historyHeaderBottom; self.headerOffset = headerOffset
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UICollectionView { context.coordinator.makeCollection() }
    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh()
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate {
        enum Entry: Hashable, Sendable {
            case historyHeader, past(Int), playerHeader, queueHeader, song(UUID), add, autoplay
        }
        var parent: NativeQueueList
        private weak var collection: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, Entry>!
        private var tracks: [Entry: MusicTrack] = [:]
        private var didPositionQueue = false
        private var lastTypeface: String?
        private var lastSource: String?
        private var lastHeaderRevision: Int?
        private var lastHeaderHeight: CGFloat?
        private var historyRevealed = false
        private var hasHistory = false
        private let historyFeedback = UIImpactFeedbackGenerator(style: .soft)

        init(parent: NativeQueueList) { self.parent = parent }

        func makeCollection() -> UICollectionView {
            let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
                guard let self else { return nil }
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.backgroundColor = .clear
                configuration.showsSeparators = false
                configuration.headerMode = index == 0 && self.hasHistory ? .supplementary : .none
                configuration.trailingSwipeActionsConfigurationProvider = { [weak self] index in self?.swipeActions(at: index) }
                let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                section.contentInsets.bottom = index == 0 && self.hasHistory ? Layout.historySectionGap : 0
                for header in section.boundarySupplementaryItems { header.pinToVisibleBounds = true }
                return section
            }
            let view = QueueCollectionView(frame: .zero, collectionViewLayout: layout)
            view.backgroundColor = .clear
            view.accessibilityIdentifier = "player-queue-list"
            view.overrideUserInterfaceStyle = .dark
            view.contentInsetAdjustmentBehavior = .never
            view.delegate = self
            view.dragInteractionEnabled = true
            view.alwaysBounceVertical = true
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
            let historyHeader = UICollectionView.SupplementaryRegistration<QueueHistoryHeader>(
                elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, _ in
                    self?.configureHistoryHeader(cell)
                }
            dataSource.supplementaryViewProvider = { collection, _, index in
                collection.dequeueConfiguredReusableSupplementary(using: historyHeader, for: index)
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
            let history = Array(parent.history.filter { $0.id != parent.playback.current?.id }.reversed())
            let historyChanged = hasHistory != !history.isEmpty
            hasHistory = !history.isEmpty
            if historyChanged { didPositionQueue = false }
            var historyEntries: [Entry] = []
            var entries: [Entry] = []
            var updated: [Entry: MusicTrack] = [:]
            if !history.isEmpty {
                for (index, track) in history.enumerated() { historyEntries.append(.past(index)); updated[.past(index)] = track }
            }
            entries.append(.playerHeader)
            entries.append(.queueHeader)
            for item in upcoming { entries.append(.song(item.id)); updated[.song(item.id)] = item.track }
            entries.append(.add)
            if parent.settings.autoplayRadio { entries.append(.autoplay) }
            let old = dataSource.snapshot()
            let allEntries = historyEntries + entries
            let changes = allEntries.filter { updated[$0] != tracks[$0] }
            let fontChanged = lastTypeface != parent.typeface
            let sourceChanged = lastSource != parent.playback.queueSource
            let headerChanged = lastHeaderHeight != parent.headerHeight
            let headerContentChanged = lastHeaderRevision != parent.headerRevision
            lastHeaderRevision = parent.headerRevision
            lastHeaderHeight = parent.headerHeight
            lastSource = parent.playback.queueSource
            lastTypeface = parent.typeface
            tracks = updated
            if old.itemIdentifiers == allEntries && changes.isEmpty && !fontChanged && !sourceChanged && !headerChanged && !historyChanged && !headerContentChanged {
                return
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Entry>()
            snapshot.appendSections([0, 1])
            snapshot.appendItems(historyEntries, toSection: 0)
            snapshot.appendItems(entries, toSection: 1)
            // Headers have changing disabled states, independent of the song metadata.
            let reconfigure = Set(fontChanged ? allEntries : changes).union([.queueHeader, .historyHeader, .playerHeader])
            snapshot.reconfigureItems(allEntries.filter { reconfigure.contains($0) && old.indexOfItem($0) != nil })
            if historyChanged || fontChanged || headerChanged { collection.collectionViewLayout.invalidateLayout() }
            dataSource.apply(snapshot, animatingDifferences: didPositionQueue && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                self?.positionQueue()
                self?.refreshVisibleHistoryHeader()
            }
        }

        private func configureHistoryHeader(_ cell: QueueHistoryHeader) {
            cell.apply(UIHostingConfiguration { [weak self] in
                if let self {
                    self.row(.historyHeader).environment(self.parent.settings).environment(\.appTypeface, self.parent.typeface)
                }
            }.margins(.all, 0))
        }

        private func refreshVisibleHistoryHeader() {
            collection?.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
                .compactMap { $0 as? QueueHistoryHeader }.forEach(configureHistoryHeader)
        }

        private func positionQueue() {
            guard let collection, collection.bounds.width > 0, collection.bounds.height > 0,
                  let index = dataSource?.indexPath(for: .playerHeader),
                  let attributes = collection.layoutAttributesForItem(at: index) else { return }
            let tail = collection.contentSize.height - attributes.frame.minY
            let padding = max(Layout.queueProgressOverlap, collection.bounds.height - tail)
            if collection.contentInset.bottom != padding { collection.contentInset.bottom = padding }
            if !didPositionQueue {
                didPositionQueue = true
                collection.scrollToItem(at: index, at: .top, animated: false)
            }
            updateHeaderOffset(collection)
            clipUnderHistoryHeader(collection)
        }

        /// The current-song header shares the queue's scroll position; history lives above it.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard didPositionQueue, let collection else { return }
            updateHeaderOffset(collection)
            clipUnderHistoryHeader(collection)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            historyFeedback.prepare()
        }

        private func updateHeaderOffset(_ view: UICollectionView) {
            guard let index = dataSource?.indexPath(for: .playerHeader),
                  let attributes = view.layoutAttributesForItem(at: index) else { return }
            let offset = attributes.frame.minY - view.contentOffset.y
            parent.headerOffset(offset)
            // Native scroll physics provide resistance; crossing the reveal threshold clicks once.
            if hasHistory, view.isDragging, offset > Layout.historyRevealThreshold, !historyRevealed {
                historyRevealed = true
                historyFeedback.impactOccurred()
            } else if offset < Layout.historyRevealReset {
                historyRevealed = false
            }
        }

        /// History rows stop below their pinned heading instead of showing through or above History/Clear.
        private func clipUnderHistoryHeader(_ view: UICollectionView) {
            let heading = view.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0))
            let bottom = hasHistory ? max(0, (heading?.frame.maxY ?? view.bounds.minY) - view.bounds.minY) : 0
            parent.historyHeaderBottom(bottom)
            let cutoff = view.bounds.minY + bottom
            for index in view.indexPathsForVisibleItems {
                guard let cell = view.cellForItem(at: index) else { continue }
                if bottom <= 0 || cell.frame.minY >= cutoff { cell.layer.mask = nil; continue }
                let mask = cell.layer.mask ?? CALayer()
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let top = min(cell.bounds.height, max(0, cutoff - cell.frame.minY))
                mask.backgroundColor = UIColor.black.cgColor
                mask.frame = CGRect(x: 0, y: top, width: cell.bounds.width, height: max(0, cell.bounds.height - top))
                cell.layer.mask = mask
                CATransaction.commit()
            }
        }

        /// History, headers and Add Songs never become destinations for an upcoming song.
        func collectionView(_ collectionView: UICollectionView,
                            targetIndexPathForMoveOfItemFromOriginalIndexPath original: IndexPath,
                            atCurrentIndexPath current: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
            let items = dataSource.snapshot().itemIdentifiers(inSection: 1)
            let positions = items.indices.filter { if case .song = items[$0] { return true }; return false }
            guard let first = positions.first, let last = positions.last else { return current }
            return IndexPath(item: min(max(proposed.section == 1 ? proposed.item : first, first), last), section: 1)
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
            case .playerHeader:
                parent.headerView.frame(minHeight: parent.headerHeight)
            case .queueHeader:
                header(parent.playback.queueSource == nil ? "ios-queue" : "ios-continue-playing",
                    identifier: "queue-clear", disabled: parent.playback.upcomingItems.isEmpty,
                    subtitle: parent.playback.queueSource.map { String(format: String(localized: "ios-queue-source"), $0) }) { [weak self] in self?.parent.playback.clearUpcomingQueue() }
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

        private func header(_ title: LocalizedStringKey, identifier: String, disabled: Bool, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Layout.compact / 2) {
                    Text(title).appFont(.headline)
                    if let subtitle { Text(subtitle).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
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
            ArtworkView(track: track, side: Layout.rowArtwork, cornerRadius: Layout.rowArtworkRadius).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.compact / 2) {
                Text(track.title).appFont(.body).foregroundStyle(.white).lineLimit(1)
                Text(track.artist).appFont(.subheadline).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            }
            Spacer(minLength: Layout.compact)
        }
        .padding(.vertical, Layout.compact / 2)
        .frame(maxWidth: .infinity, minHeight: Layout.control, alignment: .leading).contentShape(Rectangle())
    }
}

/// A genuine supplementary view hosts the pinned History controls with native self-sizing.
private final class QueueHistoryHeader: UICollectionReusableView {
    private var hosted: (UIView & UIContentView)?

    func apply(_ configuration: any UIContentConfiguration) {
        if let hosted { hosted.configuration = configuration; return }
        let content = configuration.makeContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hosted = content
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let size = systemLayoutSizeFitting(CGSize(width: attributes.size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        attributes.size.height = max(Layout.control, size.height)
        return attributes
    }
}
