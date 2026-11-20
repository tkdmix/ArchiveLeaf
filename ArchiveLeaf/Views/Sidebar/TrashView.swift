import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TrashView: View {
    @Bindable var viewModel: ArchiveViewModel
    /// What the pane's own commands act on, and what the window shows beside it. The phone shows
    /// one thing at a time and picks by tapping, so it has nothing to keep here.
    var selection: Binding<Set<UUID>> = .constant([])
    /// Selection mode belongs to the window's canonical browsing state; this list only projects it.
    var isSelectingItems: Binding<Bool> = .constant(false)
    /// Whether this pane carries its own title, as it does wherever it is the whole screen.
    var showsContentTitle = false
    /// A wide reader keeps its file on screen beside the Trash. The compact reader leaves this
    /// nil and preserves the Trash's existing row behaviour.
    var onSelectFile: ((UUID) -> Void)? = nil
    /// What the confirmation is about. Several at once, since several can be chosen.
    @State private var itemsPendingPermanentDeletion: [ArchiveItem] = []
    @State private var isConfirmingEmptyTrash = false
    /// How this list is arranged, and only for as long as it is open. Kept here rather than beside
    /// the archive's own sort order for two reasons: "date" would mean the day a file was imported
    /// in one list and the day it was discarded in this one, and the Trash is a place to pass
    /// through — every visit begins with what was thrown away last, which is what the reader means
    /// by opening it at all.
    @State private var order = ArchiveTrashOrder.discarded
    @State private var isAscending = ArchiveTrashOrder.discarded.beginsAscending

    var body: some View {
        Group {
            if viewModel.isLoadingTrash {
                ArchiveLoadingView()
            } else if viewModel.trashedFolders.isEmpty && viewModel.trashedFiles.isEmpty {
                // Inside something that scrolls, so that pulling down still reaches the archive.
                // An empty Trash is exactly when the reader wants to check whether it is really
                // empty, and a view that does not scroll has nothing to pull.
                emptyTrash
            } else {
                #if os(macOS)
                ArchiveItemTable(
                    items: trashedItems,
                    viewModel: viewModel,
                    selection: selection,
                    commands: trashCommands,
                    detail: comesWith
                )
                #else
                if isSelectingItems.wrappedValue {
                    List(selection: selection) {
                        ArchiveTitledSection("Trash", isShowingContentTitle: showsContentTitle) {
                            ForEach(trashedItems) { item in
                                itemLabel(item).tag(item.id)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    List {
                        ArchiveTitledSection("Trash", isShowingContentTitle: showsContentTitle) {
                            ForEach(trashedItems) { item in
                                trashRow(item)
                            }
                        }
                    }
                }
                #endif
            }
        }
        #if !os(macOS)
        // Two verbs rather than the archive's four, decided by the same `ArchiveItemSelection`:
        // what is in the Trash can come back or go for good, and nothing else.
        .archiveSelectionBar(
            isSelecting: isSelectingItems,
            canSelect: !trashedItems.isEmpty
        ) { showsWords in
            ArchiveTrashSelectionActions(
                selection: chosenItems,
                isOffline: viewModel.isOfflineMode,
                showsWords: showsWords,
                restore: { items in Task { await viewModel.restore(items) } },
                deletePermanently: { items in itemsPendingPermanentDeletion = items }
            )
        }
        #endif
        #if os(macOS)
        .navigationTitle("Trash")
        #else
        .archiveContentTitleChrome(showsContentTitle, barTitle: Text("Trash"))
        #endif
        .task { await viewModel.loadTrash() }
        // Pulled down like every other list. The Trash is read from the same archive as the rest
        // and goes stale the same way. Waited on rather than left to the refresh's own tail, so
        // the spinner is still turning while the Trash itself is being read.
        .refreshable {
            await viewModel.refresh()
            await viewModel.loadTrash()
        }
        // What is selected first, then what empties the whole pane — which, being the one that
        // cannot be undone at all, sits at the end.
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                Button("Restore", systemImage: "arrow.uturn.backward") { restoreSelected() }
                    .disabled(isSelectionUnavailable)
            }
            ToolbarItem {
                Button("Delete Permanently", systemImage: "xmark.bin", role: .destructive) {
                    itemsPendingPermanentDeletion = selected
                }
                .disabled(isSelectionUnavailable)
            }
            #endif
            ToolbarItem {
                sortMenu
            }
            ToolbarItem {
                Button("Empty Trash…", systemImage: "trash.slash", role: .destructive) {
                    isConfirmingEmptyTrash = true
                }
                .disabled(
                    viewModel.isOfflineMode
                        || (viewModel.trashedFolders.isEmpty && viewModel.trashedFiles.isEmpty)
                )
            }
        }
        // Through the shared one, like every other confirmation in the app: the value is handed to
        // the button rather than read back out of state that the dialog has already cleared.
        .archiveConfirmation(
            itemsPendingPermanentDeletion.count > 1
                ? "Permanently Delete These Items?"
                : "Permanently Delete This Item?",
            presenting: $itemsPendingPermanentDeletion,
            confirmTitle: "Delete Permanently",
            message: { _ in
                Text("This removes the item and its stored content from iCloud. A folder deletion also removes everything inside it. This cannot be undone.")
            }
        ) { items in
            Task {
                for item in items { await viewModel.permanentlyDelete(item) }
            }
        }
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task { await viewModel.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every item in Trash and its stored content from iCloud. This cannot be undone.")
        }
        .alert(
            "Trash Deletion",
            isPresented: Binding(
                get: { viewModel.trashResultMessage != nil },
                set: { if !$0 { viewModel.clearTrashResult() } }
            )
        ) {
            Button("OK", action: viewModel.clearTrashResult)
        } message: {
            Text(viewModel.trashResultMessage ?? "")
        }
        .alert(
            "Trash Operation Failed",
            isPresented: Binding(
                get: { viewModel.trashErrorMessage != nil },
                set: { if !$0 { viewModel.clearTrashError() } }
            )
        ) {
            Button("OK", action: viewModel.clearTrashError)
        } message: {
            Text(viewModel.trashErrorMessage ?? "Unknown error")
        }
    }

    /// Compact rows have no primary button: their actions are reached by swiping or holding. A
    /// wide reader makes only file rows a primary button, because it has a viewer beside the list.
    @ViewBuilder
    private func trashRow(_ item: ArchiveItem) -> some View {
        Group {
            #if !os(macOS)
            if case .file(let file) = item, let onSelectFile {
                Button { onSelectFile(file.id) } label: { itemLabel(item) }
                    .buttonStyle(.plain)
            } else {
                itemLabel(item)
            }
            #else
            itemLabel(item)
            #endif
        }
        .contextMenu {
            if !viewModel.isOfflineMode {
                Button("Restore", systemImage: "arrow.uturn.backward") { restore(item) }
                Divider()
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    itemsPendingPermanentDeletion = [item]
                }
            }
        }
        #if !os(macOS)
        // Trailing edge only: a leading swipe is the iPad's own sidebar gesture. Permanent
        // deletion remains in the contextual menu, while the row shortcut is restorative.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !viewModel.isOfflineMode {
                Button { restore(item) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                    .tint(.accentColor)
            }
        }
        #endif
    }

    #if os(macOS)
    private var isSelectionUnavailable: Bool { viewModel.isOfflineMode || selected.isEmpty }

    private func restoreSelected() {
        // The whole selection in one write, as the phone's bar of actions does.
        Task { await viewModel.restore(selected) }
    }
    #endif

    /// Everything chosen, in the order the list shows it.
    private var selected: [ArchiveItem] {
        trashedItems.filter { selection.wrappedValue.contains($0.id) }
    }

    /// What has been chosen, resolved against the very list on screen so that an id with no row
    /// makes the whole selection invalid rather than acting on part of it.
    private var chosenItems: ArchiveItemSelection {
        ArchiveItemSelection(items: selected, requestedIDs: selection.wrappedValue)
    }

    /// Newest first, folders and files together: what was thrown away most recently is what is
    /// most likely being looked for.
    @ViewBuilder
    private var emptyTrash: some View {
        let message = ContentUnavailableView(
            "Trash Is Empty",
            systemImage: "trash",
            description: Text("Files moved to Trash will appear here.")
        )
        #if os(macOS)
        message
        #else
        GeometryReader { proxy in
            ScrollView {
                message.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        #endif
    }

    /// The same shape as the archive's own sort control, so that choosing an order reads the same
    /// wherever it is offered: the one in force carries an arrow that is both the tick and the
    /// direction, and choosing it again turns the order around.
    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            ForEach(ArchiveTrashOrder.allCases) { candidate in
                Button {
                    if order == candidate {
                        isAscending.toggle()
                    } else {
                        order = candidate
                        isAscending = candidate.beginsAscending
                    }
                } label: {
                    if order == candidate {
                        Label(
                            candidate.title,
                            systemImage: isAscending ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(candidate.title)
                    }
                }
            }
        }
        .disabled(viewModel.trashedFolders.isEmpty && viewModel.trashedFiles.isEmpty)
    }

    /// One list, arranged the way the reader asked for.
    ///
    private var trashedItems: [ArchiveItem] {
        ArchiveTrashArrangement.ordered(
            viewModel.trashedFolders.map(ArchiveItem.folder)
                + viewModel.trashedFiles.map(ArchiveItem.file),
            by: order,
            ascending: isAscending
        )
    }

    /// What a folder brings back with it, which its name alone never said.
    private func comesWith(_ item: ArchiveItem) -> String? {
        guard case .folder(let folder) = item,
              let count = viewModel.trashedFolderItemCounts[folder.id],
              count > 0 else {
            return nil
        }
        return String(localized: "\(count) items inside")
    }

    #if os(macOS)
    /// Acts on everything chosen, which the table has already made sure includes the row that was
    /// right-clicked.
    private func trashCommands(_ item: ArchiveItem, in table: NSTableView, row: Int) -> NSMenu {
        let menu = NSMenu()
        let isEditable = !viewModel.isOfflineMode
        menu.addItem(ActionMenuItem(title: String(localized: "Restore"), isEnabled: isEditable) {
            restoreSelected()
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(
            title: String(localized: "Delete Permanently"),
            isEnabled: isEditable
        ) {
            itemsPendingPermanentDeletion = selected
        })
        return menu
    }
    #endif

    /// A file here reads as it reads everywhere else, picture and all. It was showing the symbol
    /// for its format instead — the Mac's Trash moved to the shared list and took its thumbnails
    /// with it, and this row was left behind.
    @ViewBuilder
    private func itemLabel(_ item: ArchiveItem) -> some View {
        switch item {
        case .folder(let folder):
            Label(folder.name, systemImage: "folder")
        case .file(let file):
            ArchiveFileLabel(file: file, viewModel: viewModel)
        }
    }

    private func restore(_ item: ArchiveItem) {
        Task {
            switch item {
            case .folder(let folder): await viewModel.restore(folder)
            case .file(let file): await viewModel.restore(file)
            }
        }
    }
}
