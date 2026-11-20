import SwiftUI

#if !os(macOS)
/// The wide iPad reader. The browser and viewer both project the same `ArchiveBrowsingState` that
/// `RootView` owns, so changing between this layout and the compact reader cannot leave a second
/// navigation or selection state behind.
struct ArchiveTabletRootView: View {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var browsingState: ArchiveBrowsingState
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: (any ArchiveCaching)?
    let snapshotCache: (any ArchiveSnapshotCaching)?
    let bookmarkImporter: (any BookmarkImporting)?
    @State private var isViewerMaximized = false

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                if !isViewerMaximized {
                    ArchiveMobileRootView(
                        viewModel: viewModel,
                        browsingState: $browsingState,
                        archiveResetter: archiveResetter,
                        incompleteImportPurger: incompleteImportPurger,
                        archiveBackupService: archiveBackupService,
                        archiveCache: archiveCache,
                        snapshotCache: snapshotCache,
                        bookmarkImporter: bookmarkImporter,
                        presentsFocusedFileInStack: false,
                        onSelectFile: selectFile
                    )
                    .frame(width: ArchiveTabletLayout.browserWidth)
                    .accessibilityIdentifier("archiveTabletBrowserPane")
                    .accessibilityElement(children: .contain)

                    Divider()
                }

                // This is the only navigation container around the viewer. Its width is the
                // HStack's remaining visible area, never the window's full width.
                NavigationStack {
                    detailContent
                        // Keep the layout control in the same toolbar scope as the document
                        // controls so opening a file cannot replace it.
                        .toolbar { viewerVisibilityToolbarItem }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("archiveTabletViewerPane")
                .accessibilityElement(children: .contain)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if browsingState.selectedItemIDs.count > 1 {
            ManySelectedView(count: browsingState.selectedItemIDs.count)
        } else if let onlyID = browsingState.selectedItemIDs.first, let item = shownItem(onlyID) {
            ArchiveDetailView(
                item: item,
                viewModel: viewModel,
                onShowFile: selectFile
            )
        } else if let focusedFileID = browsingState.focusedFileID, let file = shownFile(focusedFileID) {
            ArchiveDetailView(
                item: .file(file),
                viewModel: viewModel,
                onShowFile: selectFile
            )
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

    private var viewerVisibilityToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation {
                    isViewerMaximized.toggle()
                }
            } label: {
                if isViewerMaximized {
                    Label("Show Browser", systemImage: "sidebar.left")
                } else {
                    Label("Maximize Viewer", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            .accessibilityIdentifier("archiveTabletViewerVisibility")
        }
    }

    /// Trash is still a shelf: a file there remains readable before the person decides whether to
    /// restore or delete it. Active and trashed files therefore share the same detail resolution.
    private func shownFile(_ id: UUID) -> ArchiveFile? {
        viewModel.file(id: id) ?? viewModel.trashedFiles.first { $0.id == id }
    }

    private func shownItem(_ id: UUID) -> ArchiveItem? {
        if let folder = viewModel.folder(id: id)
            ?? viewModel.trashedFolders.first(where: { $0.id == id }) {
            return .folder(folder)
        }
        return shownFile(id).map(ArchiveItem.file)
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
