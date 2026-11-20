import SwiftUI

#if !os(macOS)
/// The archive's folders on the phone, drawn the way the Mac's folder pane draws them: one tree
/// that opens and closes in place, with the number of files beside each row.
///
/// The phone used to push into a folder to see the folders inside it, which meant the shape of the
/// archive could only be learned one screen at a time. The same shape now reads the same on both.
/// Tapping a row still opens that folder's files — the tree says where things are, the pushed
/// screen shows what is in them.
///
/// There is no row named "Folders" above the tree: the tab at the foot of the screen is already
/// called that, and the title above it says it again. On the Mac and the iPad the heading earns its
/// line, because there the four places share one list and the heading is what separates them.
struct FolderTreeListView: View {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var path: [ArchiveRoute]
    /// iPad's fixed browser column puts this title in the scrollable list so the navigation bar
    /// can reserve its width for back navigation and archive actions.
    var showsContentTitle = false
    @State private var expansion = FolderExpansion()

    var body: some View {
        List {
            // The title is a header, not a row: keeping it outside the section's row chrome lets
            // the single Unsorted destination keep all four of its rounded corners.
            ArchiveTitledSection("Folders", isShowingContentTitle: showsContentTitle) {
                unsortedRow
            }

            Section {
                ForEach(viewModel.folders(in: nil)) { folder in
                    FolderTreeRow(
                        folder: folder,
                        viewModel: viewModel,
                        expansion: expansion,
                        path: $path
                    )
                }
            }
        }
        .archiveContentTitleChrome(showsContentTitle, barTitle: Text("Folders"))
        .refreshable { await viewModel.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    viewModel.beginCreatingFolder(in: nil)
                }
                .disabled(viewModel.isOfflineMode)
            }
            // The order of the folders is decided from the screen that shows them. Manual order was
            // taken away, so without this the one pane a reader spends most of their time in had no
            // say in how it was arranged.
            ToolbarItem {
                ArchiveSortMenu(
                    viewModel: viewModel,
                    modes: [.displayName, .importedAt]
                )
            }
        }
    }

    /// Kept above the folders and never sorted among them.
    ///
    /// Unsorted is not a folder. It is what guarantees that this pane can reach every item in the
    /// archive: a file always has a place, even when that place is nowhere in particular, and
    /// without this row those files would be unreachable here. Tags need no equivalent — an item
    /// may honestly carry no tag, and it is still reachable through its folder.
    private var unsortedRow: some View {
        Button {
            path = [.unsorted]
        } label: {
            ArchiveSourceRowLabel(
                name: String(localized: "Unsorted Files"),
                systemImage: "tray",
                itemCount: viewModel.itemCount(inFolderWithID: nil),
                navigates: true
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("source-unsorted")
    }
}

/// One folder and, if it is open, the folders inside it.
///
/// Written out rather than left to `DisclosureGroup` for two reasons: each row's open state is ours
/// to keep — the group holds that privately, and it is worth remembering between launches — and the
/// group's label swallows the tap, so a folder with anything inside it could be opened and closed
/// but never entered.
private struct FolderTreeRow: View {
    let folder: ArchiveFolder
    @Bindable var viewModel: ArchiveViewModel
    let expansion: FolderExpansion
    @Binding var path: [ArchiveRoute]
    var depth: Int = 0

    var body: some View {
        let children = viewModel.folders(in: folder.id)
        row(hasChildren: !children.isEmpty)
        if !children.isEmpty, expansion.isOpen(folder.id) {
            ForEach(children) { child in
                // Erased because a view cannot name itself in its own body's type.
                AnyView(
                    FolderTreeRow(
                        folder: child,
                        viewModel: viewModel,
                        expansion: expansion,
                        path: $path,
                        depth: depth + 1
                    )
                )
            }
        }
    }

    /// Opens the folder by pushing everything above it as well.
    ///
    /// A jump from the tree straight to somewhere deep is right — that is what a tree is for — but
    /// arriving there with nothing underneath meant going back landed on the tree again. Pushing
    /// the chain lets the reader step up one level at a time, and the system's own back button
    /// names the parent without a control of our own.
    private func row(hasChildren: Bool) -> some View {
        Button {
            path = viewModel.folderChain(to: folder.id).map { ArchiveRoute.folder($0.id) }
        } label: {
            ArchiveSourceRowLabel(
                name: folder.name,
                systemImage: "folder",
                itemCount: viewModel.itemCount(inFolderWithID: folder.id),
                disclosure: hasChildren ? expansion.binding(for: folder.id) : nil,
                navigates: true
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Named rather than read off the row's words: a test that spells out a label is a test of
        // the current wording and of the current language, and both change.
        .accessibilityIdentifier("folder-row-\(folder.name)")
        .contextMenu {
            ArchiveItemMenu(item: .folder(folder), viewModel: viewModel)
        }
        // The tree is another view of the same folders as the folder contents list. Keep its
        // one row-level action identical: trailing only, confirmation before it moves anything,
        // and no full swipe that could bypass that question.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !viewModel.isOfflineMode {
                Button(role: .destructive) {
                    viewModel.itemsPendingTrash = [.folder(folder)]
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
    }
}
#endif
