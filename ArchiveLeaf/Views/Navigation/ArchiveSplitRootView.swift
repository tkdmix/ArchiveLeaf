#if os(macOS)
import SwiftUI

/// Converts the sidebar's presentation value into the canonical browsing location.
func archiveBrowsingLocation(for source: ArchiveSource?) -> ArchiveBrowsingLocation? {
    switch source {
    case .folders: return .folders
    case .folder(let id): return .unsortedOrFolder(id)
    case .favorites: return .favorites
    case .tag(let path): return .tag(path: path)
    case .trash: return .trash
    case nil: return nil
    }
}

/// Converts the canonical browsing location into the sidebar's presentation value.
func archiveSource(for location: ArchiveBrowsingLocation) -> ArchiveSource {
    switch location {
    case .folders: return .folders
    case .unsorted: return .folder(nil)
    case .folder(let id): return .folder(id)
    case .favorites: return .favorites
    case .tag(let path): return .tag(path: path)
    case .trash: return .trash
    }
}

/// The source at the root of the column containing a location.
func archiveRootSource(for location: ArchiveBrowsingLocation) -> ArchiveSource {
    switch location {
    case .folders, .unsorted, .folder: return .folders
    case .favorites: return .favorites
    case .tag: return .tag(path: "")
    case .trash: return .trash
    }
}

private extension ArchiveBrowsingLocation {
    static func unsortedOrFolder(_ id: UUID?) -> Self {
        guard let id else { return .unsorted }
        return .folder(id)
    }
}

struct ArchiveSplitRootView: View {
    @Bindable var viewModel: ArchiveViewModel
    /// The canonical state is held by RootView so width-driven layout replacement on iPad cannot
    /// rebuild the reader's location or selection.
    @Binding var browsingState: ArchiveBrowsingState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var expansion = FolderExpansion()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            loadAwareSidebar
                // Settings is a destination of the app, so it stands with the window's own
                // controls rather than with the pane's — beside the sidebar toggle, which is the
                // other thing here that belongs to the window and not to what is being read.
                //
                // It is declared on this column and outside `loadAwareSidebar`, so that neither
                // the archive still loading nor the middle pane pushing a folder can take it away.
                // Declared on the split view it lasted until the first push: a stack's own bar
                // replaces what the window put there, and choosing a folder in the sidebar is a
                // push.
                //
                // On macOS 26 this shares a capsule with the column's Back button, which files a
                // destination of the app under navigation and is the wrong statement to make. It
                // stands anyway, because the capsule cannot be split from here — a `ToolbarSpacer`
                // reaches only within one toolbar declaration, and Back belongs to the next
                // column's. The placement that does leave the capsule, `.primaryAction`, puts the
                // gear inside the sidebar column, where collapsing the sidebar sends it to the
                // overflow chevron. A gear in the wrong capsule can still be seen and pressed; a
                // gear behind `»` cannot.
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .help("Settings")
                        .accessibilityIdentifier("settings-button")
                    }
                }

                                .navigationSplitViewColumnWidth(min: 150, ideal: 200)
                        } content: {
            NavigationStack(path: columnPath) {
                sourceContents
                    .navigationDestination(for: ArchiveRoute.self, destination: pushed)
            }
            .overlay {
                if viewModel.isRefreshing || viewModel.isImporting || viewModel.isInspectingImports {
                    ProgressView()
                        .controlSize(.small)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

                        .navigationSplitViewColumnWidth(min: 200, ideal: 380)
                    } detail: {
            detailContent

                                .navigationSplitViewColumnWidth(min: 180, ideal: 480)
                        }
        // A place that no longer exists is reconciled by RootView, for both layouts at once: it
        // owns the state, and the compact layout needs the same recovery this one does. What is
        // left here is only what this column presented.
        .task { discardMissingItems() }
        .onChange(of: viewModel.loadState) { _, _ in discardMissingItems() }
        .onChange(of: viewModel.folders) { _, _ in discardMissingItems() }
        .onChange(of: viewModel.files) { _, _ in discardMissingItems() }
        #if os(macOS)
        .archiveItemFlows(viewModel: viewModel)
        .focusedSceneValue(\.reloadArchiveAction) {
            Task { await viewModel.refresh() }
        }
        #endif
    }

    /// This binding is only an adapter for NavigationStack. It is always recomputed from the
    /// canonical location; stack gestures write a new location or focus, never local path state.
    private var columnPath: Binding<[ArchiveRoute]> {
        Binding(
            get: {
                archiveRoutePath(
                    for: browsingState.location,
                    folderIDs: folderRouteIDs,
                    tagPaths: tagRoutePaths
                )
            },
            set: { newPath in applyColumnPath(newPath) }
        )
    }

    private var folderRouteIDs: [UUID] {
        guard case .folder(let id) = browsingState.location else { return [] }
        return viewModel.folderChain(to: id).map(\.id)
    }

    private var tagRoutePaths: [String] {
        guard case .tag(let path) = browsingState.location, !path.isEmpty else { return [] }
        return viewModel.tagChain(to: path).map(\.id)
    }

    /// Sidebar highlighting is a pure projection of location. It never follows a peer path.
    private var chosenSource: Binding<ArchiveSource?> {
        Binding(
            get: { archiveSource(for: browsingState.location) },
            set: { source in
                guard let location = archiveBrowsingLocation(for: source),
                      location != browsingState.location else {
                    return
                }
                browsingState.show(location)
            }
        )
    }

    private var selectedItemIDs: Binding<Set<UUID>> {
        Binding(
            get: { browsingState.selectedItemIDs },
            set: { browsingState.replaceSelectedItems($0) }
        )
    }

    /// The compact folder list needs a Boolean binding for its standard Select/Done control.
    /// It is an adapter only: entering and leaving the mode remain canonical state transitions.
    private var selectionMode: Binding<Bool> {
        Binding(
            get: { browsingState.isSelectingItems },
            set: { isSelecting in
                guard isSelecting != browsingState.isSelectingItems else { return }
                if isSelecting {
                    browsingState.beginSelecting()
                } else {
                    browsingState.finishSelecting()
                }
            }
        )
    }

    private var rootSource: ArchiveSource { archiveRootSource(for: browsingState.location) }


    private func applyColumnPath(_ path: [ArchiveRoute]) {
        if case .file(let id)? = path.last {
            browsingState.focusFile(id)
            viewModel.noteFileChosen(id)
            return
        }

        guard let location = archiveBrowsingLocation(
            forColumnPath: path,
            from: browsingState.location
        ), location != browsingState.location else {
            return
        }
        browsingState.show(location)
    }

    /// What the column begins with: the place the sidebar has already chosen. The Mac's sidebar
    /// carries the whole tree, so the column shows that place's contents rather than a tree of its
    /// own.
    @ViewBuilder
    private var sourceContents: some View {
        switch rootSource {
        case .folders:
            ArchiveFolderContentsView(
                parentFolderID: nil,
                viewModel: viewModel,
                path: columnPath,
                onSelectFile: selectFile,
                selection: selectedItemIDs,
                isSelectingItems: selectionMode,
                isArchiveRoot: true
            )
        case .favorites:
            FavoritesView(
                viewModel: viewModel,
                onSelectFile: selectFile,
                selection: selectedItemIDs
            )
        case .tag(let path):
            TagContentsView(
                path: path,
                viewModel: viewModel,
                onSelectFile: selectFile,
                onSelectTag: openTag,
                selection: selectedItemIDs
            )
        case .trash:
            TrashView(viewModel: viewModel, selection: selectedItemIDs)
        case .folder:
            ContentUnavailableView("Select a Folder", systemImage: "folder")
        }
    }

    /// Opening a folder from the column goes deeper in that same column, and the system's own back
    /// button is the way out. A file is not pushed: it is shown in the pane beside this one.
    @ViewBuilder
    private func pushed(_ route: ArchiveRoute) -> some View {
        switch route {
        case .folder(let id):
            ArchiveFolderContentsView(
                parentFolderID: id,
                viewModel: viewModel,
                path: columnPath,
                onSelectFile: selectFile,
                selection: selectedItemIDs,
                isSelectingItems: selectionMode
            )
        case .unsorted:
            ArchiveFolderContentsView(
                parentFolderID: nil,
                viewModel: viewModel,
                path: columnPath,
                onSelectFile: selectFile,
                selection: selectedItemIDs,
                isSelectingItems: selectionMode,
                showsFolders: false
            )
        case .tag(let path):
            TagContentsView(
                path: path,
                viewModel: viewModel,
                onSelectFile: selectFile,
                onSelectTag: openTag,
                selection: selectedItemIDs
            )
        case .file:
            EmptyView()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if browsingState.selectedItemIDs.count > 1 {
            ManySelectedView(count: browsingState.selectedItemIDs.count)
        } else if let onlyID = browsingState.selectedItemIDs.first, let file = shownFile(onlyID) {
            ArchiveDetailView(item: .file(file), viewModel: viewModel, onShowFile: selectFile)
        } else if let focusedFileID = browsingState.focusedFileID, let file = shownFile(focusedFileID) {
            ArchiveDetailView(item: .file(file), viewModel: viewModel, onShowFile: selectFile)
        } else if browsingState.location == .trash {
            ContentUnavailableView(
                "Trash",
                systemImage: "trash",
                description: Text("Restore or permanently delete items from the list.")
            )
            .navigationTitle("Trash")
            .documentControlsPlaceholder(isShown: true)
        } else {
            ArchiveDetailView(
                item: nil,
                viewModel: viewModel,
                emptyNavigationTitle: browsingState.location == .favorites ? "Favorites" : nil
            )
        }
    }

    @ViewBuilder
    private var loadAwareSidebar: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ArchiveLoadingView(title: "Loading Archive…")
        case .empty, .loaded:
            ArchiveSourceOutline(
                viewModel: viewModel,
                selection: chosenSource,
                expansion: expansion
            )
        case .iCloudUnavailable:
            ContentUnavailableView {
                Label("iCloud Is Unavailable", systemImage: "icloud.slash")
            } description: {
                Text("Sign in to iCloud and allow ArchiveLeaf to access your private archive.")
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Archive Could Not Be Loaded", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        }
    }

    /// Lets go of a focused or selected item that a refreshed archive no longer contains. Where the
    /// reader is — the location itself — is reconciled by RootView, for both layouts at once.
    private func discardMissingItems() {
        guard viewModel.loadState == .empty || viewModel.loadState == .loaded else { return }

        let availableItemIDs = Set(
            viewModel.folders.map(\.id)
                + viewModel.files.map(\.id)
                + viewModel.trashedFolders.map(\.id)
                + viewModel.trashedFiles.map(\.id)
        )
        browsingState.reconcile(availableItemIDs: availableItemIDs)
    }

    /// Something thrown away is still something to look at before deciding: what is in the Trash
    /// reads here as it reads anywhere else.
    private func shownFile(_ id: UUID) -> ArchiveFile? {
        viewModel.file(id: id) ?? viewModel.trashedFiles.first { $0.id == id }
    }

    /// One step further into the tag tree, pushed the way opening a folder from this column is.
    private func openTag(_ path: String) {
        var routes = columnPath.wrappedValue
        routes.append(.tag(path: path))
        applyColumnPath(routes)
    }

    private func selectFile(_ id: UUID) {
        browsingState.focusFile(id)
        viewModel.noteFileChosen(id)
        if let file = viewModel.file(id: id) {
            viewModel.selection = .file(file)
        }
    }
}
#endif
