import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

struct RootView: View {
    @State private var viewModel: ArchiveViewModel
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: (any ArchiveCaching)?
    let snapshotCache: (any ArchiveSnapshotCaching)?
    let bookmarkImporter: (any BookmarkImporting)?
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// Where the reader is and what they have selected. Held here rather than inside either
    /// layout, because on iPad the two layouts replace each other as the window's width changes
    /// — including for a moment while switching apps — and state inside them does not survive
    /// that.
    /// Restored from where the reader was last time. Reconciled against the archive once it has
    /// been read, because somewhere they were can have been deleted on another device since.
    @State private var browsingState: ArchiveBrowsingState
    #if !os(macOS)
    /// Whether the list is standing beside the file rather than behind it. Which layout is on
    /// screen decides what closing a page leaves the reader looking at, and only this view knows.
    @State private var hasTwoPanes = false
    #endif
    private let browsingStateStore = ArchiveBrowsingStateStore()

    init(
        viewModel: ArchiveViewModel,
        archiveResetter: (any ArchiveResetting)? = nil,
        incompleteImportPurger: (any IncompleteImportPurging)? = nil,
        archiveBackupService: (any ArchiveBackupPackageServicing)? = nil,
        archiveCache: (any ArchiveCaching)? = nil,
        snapshotCache: (any ArchiveSnapshotCaching)? = nil,
        bookmarkImporter: (any BookmarkImporting)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        _browsingState = State(initialValue: ArchiveBrowsingStateStore().load())
        self.archiveResetter = archiveResetter
        self.incompleteImportPurger = incompleteImportPurger
        self.archiveBackupService = archiveBackupService
        self.archiveCache = archiveCache
        self.snapshotCache = snapshotCache
        self.bookmarkImporter = bookmarkImporter
    }

    var body: some View {
        Group {
            #if os(macOS)
            splitRoot
            #else
            GeometryReader { proxy in
                let twoPane = ArchiveTabletLayout.usesTwoPane(
                    availableSize: proxy.size,
                    isRegularWidth: horizontalSizeClass == .regular
                )
                Group {
                    if twoPane {
                        tabletRoot
                    } else {
                        mobileRoot
                    }
                }
                .onChange(of: twoPane, initial: true) { _, isTwoPane in
                    hasTwoPanes = isTwoPane
                }
            }
            #endif
        }
        #if !os(macOS)
        // The page belongs to the app, not to a pane: it covers everything, and the layout beneath
        // it is replaced whenever the window changes shape. Presented from here, it survives that
        // — including the change iPad makes on the way out to the Home screen and back, which used
        // to close it.
        .safariBrowser(page: Binding(
            get: { viewModel.openPage },
            set: { viewModel.openPage = $0 }
        ), onClose: pageWasClosed)
        #endif
        .safeAreaInset(edge: .top) {
            if viewModel.isOfflineMode {
                Label(
                    "Offline — showing the last downloaded archive. Changes are disabled.",
                    systemImage: "icloud.slash"
                )
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.orange.opacity(0.18))
            }
        }
        #if os(macOS)
        // Only what three usable panes need. The toolbar is not what holds this open: where its
        // controls do not fit, they collapse behind one button.
        .frame(minWidth: 620, minHeight: 480)
        #endif
        // Written down whenever it moves, so the next launch begins where this one left off.
        .onChange(of: browsingState) { _, state in
            browsingStateStore.save(state)
        }
        // The archive says which of the remembered places still exist. One that does not — a folder
        // deleted on another device — gives way to the top of its own area.
        .onChange(of: viewModel.loadState) { _, _ in reconcileRememberedPlaces() }
        .onChange(of: viewModel.folders) { _, _ in reconcileRememberedPlaces() }
        .onChange(of: viewModel.tags) { _, _ in reconcileRememberedPlaces() }
        .task {
            await viewModel.load()
            reconcileRememberedPlaces()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await viewModel.refreshConnectivity()
            }
        }
        // Coming back to the app is when something added from another device can first be noticed,
        // since nothing announces it. One rule everywhere: read again if what is on screen is more
        // than a moment old. Reading on every return meant a glance at another app and back cost a
        // whole read of the archive — and showed it, in the pane the reader was looking at.
        // Pulling down still reads immediately for anyone who will not wait.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshIfStale() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .archiveLeafArchiveDidReplace)) { notification in
            guard let snapshot = notification.object as? ArchiveSnapshot else { return }
            Task { await viewModel.adoptReplacedArchive(snapshot) }
        }
        .alert(
            "Some Files Were Not Imported",
            isPresented: Binding(
                get: { viewModel.importErrorMessage != nil },
                set: { if !$0 { viewModel.clearImportError() } }
            )
        ) {
            Button("OK", action: viewModel.clearImportError)
        } message: {
            Text(viewModel.importErrorMessage ?? "")
        }
        .alert(
            "Offline Change Not Available",
            isPresented: Binding(
                get: { viewModel.offlineOperationMessage != nil },
                set: { if !$0 { viewModel.clearOfflineOperationMessage() } }
            )
        ) {
            Button("OK") { viewModel.clearOfflineOperationMessage() }
        } message: {
            Text(viewModel.offlineOperationMessage ?? "")
        }
        // Last, so that the cover is above everything the shelf draws — and the page is put away as
        // the shelf closes, because it is the one thing the cover cannot reach. A page is presented
        // full screen from this same view, and SwiftUI will not raise a second presentation over
        // the first; leaving it would let the reader come back to whatever they had been reading
        // with the shelf behind it locked. Closing it costs the reader their place in the page,
        // which is the smaller loss and the only one on offer here.
        .shelfLock { viewModel.openPage = nil }
    }

    #if !os(macOS)
    /// The page has been closed, and what is underneath decides what happens next.
    ///
    /// A document is still behind its links, so closing one of those simply shows the document
    /// again. A bookmark has nothing behind it: with the list standing beside it, the pane falls
    /// back to the card — which is there to fill that space, not to be arrived at — and with the
    /// list behind it, the file's screen goes away and the reader is back in the list they came
    /// from.
    private func pageWasClosed() {
        guard !hasTwoPanes,
              let id = browsingState.focusedFileID,
              viewModel.file(id: id)?.effectiveDisplayFormat == .bookmark else { return }
        browsingState.clearFocusedFile()
    }
    #endif

    private func reconcileRememberedPlaces() {
        guard viewModel.loadState == .empty || viewModel.loadState == .loaded else { return }
        browsingState.reconcileLocations(
            existingFolderIDs: Set(viewModel.folders.map(\.id)),
            existingTagPaths: Set(viewModel.tagTree.flatMap(\.selfAndDescendants).map(\.id))
        )
    }

    #if os(macOS)
    private var splitRoot: some View {
        ArchiveSplitRootView(
            viewModel: viewModel,
            browsingState: $browsingState
        )
    }
    #endif

    #if !os(macOS)
    private var mobileRoot: some View {
        ArchiveMobileRootView(
            viewModel: viewModel,
            browsingState: $browsingState,
            archiveResetter: archiveResetter,
            incompleteImportPurger: incompleteImportPurger,
            archiveBackupService: archiveBackupService,
            archiveCache: archiveCache,
            snapshotCache: snapshotCache,
            bookmarkImporter: bookmarkImporter
        )
    }

    private var tabletRoot: some View {
        ArchiveTabletRootView(
            viewModel: viewModel,
            browsingState: $browsingState,
            archiveResetter: archiveResetter,
            incompleteImportPurger: incompleteImportPurger,
            archiveBackupService: archiveBackupService,
            archiveCache: archiveCache,
            snapshotCache: snapshotCache,
            bookmarkImporter: bookmarkImporter
        )
    }
    #endif

}

#Preview {
    RootView(viewModel: ArchiveViewModel(
        repository: AppEnvironment.preview.archiveRepository,
        importPreflight: AppEnvironment.preview.importPreflight,
        archiveImporter: AppEnvironment.preview.archiveImporter
    ))
}
