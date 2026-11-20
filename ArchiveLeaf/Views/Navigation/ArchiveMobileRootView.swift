import SwiftUI

#if !os(macOS)
struct ArchiveMobileRootView: View {
    @Bindable var viewModel: ArchiveViewModel
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: (any ArchiveCaching)?
    let snapshotCache: (any ArchiveSnapshotCaching)?
    let bookmarkImporter: (any BookmarkImporting)?
    /// In a two-column layout the focused file is projected into the neighbouring detail column.
    /// Keeping it out of this stack means selecting a file leaves the browser visible.
    let presentsFocusedFileInStack: Bool
    /// In a two-column layout, every file list reports a choice directly to the neighbouring
    /// viewer instead of putting a detail screen on this browser's navigation stack.
    let onSelectFile: ((UUID) -> Void)?
    /// The one canonical state, held by RootView. Each tab's stack, the chosen tab, the focused
    /// file, and the selection are all projections of it — this layout owns none of them, because
    /// on iPad it is replaced by the split layout as the window's width changes and anything it
    /// held would be rebuilt at its initial value.
    @Binding var browsingState: ArchiveBrowsingState
    @State private var isShowingSettings = false
    /// Whether the bookmarks restored into this layout's stacks have already been let go of. One
    /// launch, one drop: doing it again would take away a page the reader has since opened.
    @State private var hasDroppedRestoredPages = false

    init(
        viewModel: ArchiveViewModel,
        browsingState: Binding<ArchiveBrowsingState>,
        archiveResetter: (any ArchiveResetting)? = nil,
        incompleteImportPurger: (any IncompleteImportPurging)? = nil,
        archiveBackupService: (any ArchiveBackupPackageServicing)? = nil,
        archiveCache: (any ArchiveCaching)? = nil,
        snapshotCache: (any ArchiveSnapshotCaching)? = nil,
        bookmarkImporter: (any BookmarkImporting)? = nil,
        presentsFocusedFileInStack: Bool = true,
        onSelectFile: ((UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        _browsingState = browsingState
        self.archiveResetter = archiveResetter
        self.incompleteImportPurger = incompleteImportPurger
        self.archiveBackupService = archiveBackupService
        self.archiveCache = archiveCache
        self.snapshotCache = snapshotCache
        self.bookmarkImporter = bookmarkImporter
        self.presentsFocusedFileInStack = presentsFocusedFileInStack
        self.onSelectFile = onSelectFile
    }

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                ArchiveLoadingView(title: "Loading Archive…")
            case .empty, .loaded:
                tabs
            case .iCloudUnavailable:
                unavailableArchive
            case .failed(let message):
                failedArchive(message)
            }
        }
        // Once, as soon as the archive is there to ask. Waiting for it is the point: at launch the
        // files have not arrived yet, so which of them is a bookmark cannot be known before this.
        .task(id: viewModel.loadState) {
            guard presentsFocusedFileInStack, !hasDroppedRestoredPages else { return }
            switch viewModel.loadState {
            case .idle, .loading: return
            case .empty, .loaded, .iCloudUnavailable, .failed: break
            }
            hasDroppedRestoredPages = true
            // Never what the reader just pressed — only what the last run left behind.
            let chosen = viewModel.chosenFileID
            browsingState.clearFocusedFiles { id in
                id != chosen && viewModel.file(id: id)?.effectiveDisplayFormat == .bookmark
            }
        }
    }

    private var tabs: some View {
        // `tabItem` rather than the `Tab` type, which would raise the deployment target to iOS 18
        // in exchange for nothing this layout needs.
        TabView(selection: chosenSection) {
            NavigationStack(path: path(for: .folders)) {
                FolderTreeListView(
                    viewModel: viewModel,
                    path: path(for: .folders),
                    showsContentTitle: true
                )
                    .navigationDestination(for: ArchiveRoute.self, destination: destination)
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Folders", systemImage: "folder") }
            .tag(ArchivePrimarySection.folders)

            NavigationStack(path: path(for: .favorites)) {
                FavoritesView(
                    viewModel: viewModel,
                    onSelectFile: onSelectFile,
                    selection: selectedItemIDs(in: .favorites),
                    isSelectingItems: selectionMode(in: .favorites),
                    showsContentTitle: true
                )
                .navigationDestination(for: ArchiveRoute.self, destination: destination)
            }
            .tabItem { Label("Favorites", systemImage: "star") }
            .tag(ArchivePrimarySection.favorites)

            NavigationStack(path: path(for: .tags)) {
                TagListView(
                    viewModel: viewModel,
                    path: path(for: .tags),
                    showsContentTitle: true
                )
                    .navigationDestination(for: ArchiveRoute.self, destination: destination)
            }
            .tabItem { Label("Tags", systemImage: "tag") }
            .tag(ArchivePrimarySection.tags)

            NavigationStack(path: path(for: .trash)) {
                TrashView(
                    viewModel: viewModel,
                    selection: selectedItemIDs(in: .trash),
                    isSelectingItems: selectionMode(in: .trash),
                    showsContentTitle: true,
                    onSelectFile: onSelectFile
                )
            }
            .tabItem { Label("Trash", systemImage: "trash") }
            .tag(ArchivePrimarySection.trash)
        }
        // Once for the whole window, which is what this modifier has always asked for. It was
        // attached in four screens at once, and on iOS several of them are alive together — a tab's
        // tree and every folder pushed on top of it. When the same question was asked of all of
        // them, one presented it and the others' rebuilding took it straight back down: the Trash
        // confirmation appeared and vanished in the same instant, and the command was silently lost.
        .archiveItemFlows(viewModel: viewModel)
        .sheet(isPresented: $isShowingSettings) {
            ArchiveSettingsSheet(
                archiveResetter: archiveResetter,
                incompleteImportPurger: incompleteImportPurger,
                archiveBackupService: archiveBackupService,
                archiveCache: archiveCache,
                snapshotCache: snapshotCache,
                bookmarkImporter: bookmarkImporter
            ) {
                isShowingSettings = false
            }
        }
    }

    /// The chosen tab. Switching leaves the tab being left exactly where it was: a tab bar is the
    /// platform's own control and every stock app's tabs remember their depth, so the canonical
    /// state keeps a place per area rather than one place for the whole archive.
    private var chosenSection: Binding<ArchivePrimarySection> {
        Binding(
            get: { browsingState.section },
            set: { browsingState.showSection($0) }
        )
    }

    /// One tab's stack, recomputed from the canonical state every time it is read.
    ///
    /// A compact layout has no detail pane, so the focused file is the last step of the stack there.
    /// In a split layout it is shown beside this browser and deliberately stays out of the stack.
    /// Pushes and pops write a location or a focus; nothing writes a path of its own.
    private func path(for section: ArchivePrimarySection) -> Binding<[ArchiveRoute]> {
        Binding(
            get: { routes(for: section) },
            set: { newPath in apply(newPath, in: section) }
        )
    }

    private func routes(for section: ArchivePrimarySection) -> [ArchiveRoute] {
        let location = browsingState.location(in: section)
        var routes = archiveRoutePath(
            for: location,
            folderIDs: folderRouteIDs(for: location),
            tagPaths: tagRoutePaths(for: location)
        )
        if presentsFocusedFileInStack,
           let focusedFileID = browsingState.focusedFileID(in: section) {
            routes.append(.file(focusedFileID))
        }
        return routes
    }

    private func apply(_ newPath: [ArchiveRoute], in section: ArchivePrimarySection) {
        guard newPath != routes(for: section) else { return }

        if case .file(let id) = newPath.last {
            browsingState.focusFile(id)
            viewModel.noteFileChosen(id)
            return
        }

        let current = browsingState.location(in: section)
        guard let location = archiveBrowsingLocation(forColumnPath: newPath, from: current) else {
            return
        }
        if location == current {
            // The list did not move; only the file's screen was popped off the top of it.
            browsingState.clearFocusedFile()
        } else {
            browsingState.show(location)
        }
    }

    private func folderRouteIDs(for location: ArchiveBrowsingLocation) -> [UUID] {
        guard case .folder(let id) = location else { return [] }
        return viewModel.folderChain(to: id).map(\.id)
    }

    private func tagRoutePaths(for location: ArchiveBrowsingLocation) -> [String] {
        guard case .tag(let path) = location, !path.isEmpty else { return [] }
        return viewModel.tagChain(to: path).map(\.id)
    }

    /// Compact lists receive a projection of the canonical selected IDs; they do not own them.
    ///
    /// Named by area, because all four areas' lists are alive at once behind the tabs and each of
    /// them reports its own selection as it is built. A word from an area that is not the one being
    /// worked in is not about this selection, and the canonical state drops it.
    private func selectedItemIDs(in section: ArchivePrimarySection) -> Binding<Set<UUID>> {
        Binding(
            get: { browsingState.isSelectingItems(in: section) ? browsingState.selectedItemIDs : [] },
            set: { browsingState.updateSelectedItems($0, in: section) }
        )
    }

    /// Adapts the standard Select/Done Boolean control to explicit canonical transitions, on behalf
    /// of one area. Entering selection does not pass an empty set through `replaceSelectedItems`,
    /// which intentionally exits selection mode for a deselected list.
    private func selectionMode(in section: ArchivePrimarySection) -> Binding<Bool> {
        Binding(
            get: { browsingState.isSelectingItems(in: section) },
            set: { browsingState.setSelecting($0, in: section) }
        )
    }

    /// Settings belongs to the archive's folder root, which is the single place it can be reached.
    ///
    /// Stated unconditionally, because a toolbar declared on a stack's root content already belongs
    /// to the root's bar alone — the folder list's own New Folder and Sort are placed the same way.
    /// Asking whether the stack is empty made this one item depend on the canonical state instead,
    /// so returning from a lower level rebuilt it after the pop had finished and the gear arrived a
    /// moment late.
    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settings-button")
        }
    }

    @ViewBuilder
    private func destination(_ route: ArchiveRoute) -> some View {
        switch route {
        case .folder(let id):
            if viewModel.folder(id: id) != nil {
                let contents = ArchiveFolderContentsView(
                    parentFolderID: id,
                    viewModel: viewModel,
                    path: path(for: .folders),
                    onSelectFile: onSelectFile,
                    selection: selectedItemIDs(in: .folders),
                    isSelectingItems: selectionMode(in: .folders),
                    showsContentTitle: true
                )
                contents
            } else {
                ContentUnavailableView("Folder Not Found", systemImage: "folder.badge.questionmark")
            }
        case .unsorted:
            let contents = ArchiveFolderContentsView(
                parentFolderID: nil,
                viewModel: viewModel,
                path: path(for: .folders),
                onSelectFile: onSelectFile,
                selection: selectedItemIDs(in: .folders),
                isSelectingItems: selectionMode(in: .folders),
                showsFolders: false,
                showsContentTitle: true
            )
            contents
        case .tag(let path):
            if let node = viewModel.tagNode(atPath: path) {
                TagContentsView(
                    path: path,
                    viewModel: viewModel,
                    onSelectFile: onSelectFile,
                    onSelectTag: { childPath in
                        var routes = self.path(for: .tags).wrappedValue
                        routes.append(.tag(path: childPath))
                        self.path(for: .tags).wrappedValue = routes
                    },
                    selection: selectedItemIDs(in: .tags),
                    isSelectingItems: selectionMode(in: .tags),
                    showsContentTitle: true
                )
                    .navigationTitle(node.name)
            } else {
                ContentUnavailableView("Tag Not Found", systemImage: "tag.slash")
            }
        case .file(let id):
            if let file = viewModel.file(id: id) {
                ArchiveDetailView(item: .file(file), viewModel: viewModel)
            } else {
                ContentUnavailableView("File Not Found", systemImage: "doc.questionmark")
            }
        }
    }

    private var unavailableArchive: some View {
        ContentUnavailableView {
            Label("iCloud Is Unavailable", systemImage: "icloud.slash")
        } description: {
            Text("Sign in to iCloud and allow ArchiveLeaf to access your private archive.")
        } actions: {
            Button("Try Again") { Task { await viewModel.load() } }
        }
    }

    private func failedArchive(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Archive Could Not Be Loaded", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await viewModel.load() } }
        }
    }
}
#endif
