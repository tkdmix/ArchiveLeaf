#if os(macOS)
import AppKit
import SwiftUI

/// What archive items offer on a right-click, wherever they are listed. Shared so that the same
/// file answers the same way in a folder as it does in Favorites.
///
/// Everything chosen, not the row under the pointer: the table has already made sure the clicked
/// row is among them, so a command reads as acting on what is highlighted. Renaming is the one
/// exception — there is only one name being typed — so it is offered for a single file alone.
@MainActor
func archiveFileCommands(
    selection: ArchiveItemSelection,
    viewModel: ArchiveViewModel,
    in table: NSTableView,
    row: Int
) -> NSMenu {
    let menu = NSMenu()
    let isEditable = !viewModel.isOfflineMode
    let files = selection.files

    // The order of the pane beside this list, read from the top: a place, a star, a tag, and the
    // Trash at the bottom — which is also the order of the tabs on a phone, left to right. The two
    // that only ever apply to one thing sit between them. The order these commands used to be in
    // was the order they had been written in, one release at a time, and nothing more.

    menu.addItem(ActionMenuItem(
        title: String(localized: "Move To…"),
        isEnabled: selection.canMove && isEditable
    ) {
        guard selection.canMove, !viewModel.isOfflineMode else { return }
        viewModel.beginMoving(selection.items)
    })

    // Adding wins where the choice is mixed: the reader who picked ten and pressed the star meant
    // to mark them, not to unmark the two that were already marked.
    let isAddingToFavorites = files.isEmpty || files.contains { !$0.isFavorite }
    menu.addItem(ActionMenuItem(
        title: isAddingToFavorites
            ? String(localized: "Add to Favorites")
            : String(localized: "Remove from Favorites"),
        isEnabled: selection.canFavorite && isEditable
    ) {
        guard selection.canFavorite, !viewModel.isOfflineMode else { return }
        // The whole selection in one write, as the phone's bar of actions does.
        Task { await viewModel.setFavorite(isAddingToFavorites, on: files.map(\.id)) }
    })

    menu.addItem(tagsMenuItem(
        selection: selection,
        viewModel: viewModel,
        isEnabled: selection.canTag && isEditable
    ))

    // ArchiveItemTable's in-place rename path is deliberately file-only. A single folder still
    // has `canRename`, but enabling this command would enter an editor that cannot save it.
    let canRenameInTable = selection.canRename && files.count == 1 && isEditable
    menu.addItem(ActionMenuItem(
        title: String(localized: "Rename"),
        isEnabled: canRenameInTable
    ) {
        guard selection.canRename, files.count == 1, !viewModel.isOfflineMode else { return }
        table.editColumn(0, row: row, with: nil, select: false)
    })

    menu.addItem(ActionMenuItem(
        title: String(localized: "Share…"),
        isEnabled: selection.canShare
    ) {
        guard selection.canShare else { return }
        let exporter = viewModel.fileExporter
        let rowRect = table.rect(ofRow: row)
        Task {
            var urls: [URL] = []
            for file in files {
                if let url = await exporter.fileURL(for: file) { urls.append(url) }
            }
            guard !urls.isEmpty else { return }
            NSSharingServicePicker(items: urls)
                .show(relativeTo: rowRect, of: table, preferredEdge: .maxY)
        }
    })

    menu.addItem(.separator())
    menu.addItem(ActionMenuItem(
        title: String(localized: "Move to Trash"),
        isEnabled: selection.canTrash && isEditable
    ) {
        guard selection.canTrash, !viewModel.isOfflineMode else { return }
        viewModel.itemsPendingTrash = selection.items
    })
    return menu
}

/// The file-only panes resolve their selected IDs from their own complete, ordered file list.
/// Keep that call site available while the folder pane needs the more general item selection.
@MainActor
func archiveFileCommands(
    selected: [ArchiveFile],
    viewModel: ArchiveViewModel,
    in table: NSTableView,
    row: Int
) -> NSMenu {
    archiveFileCommands(
        selection: ArchiveItemSelection(
            items: selected.map(ArchiveItem.file),
            requestedIDs: Set(selected.map(\.id))
        ),
        viewModel: viewModel,
        in: table,
        row: row
    )
}

/// The tags, each showing where the chosen files stand on it: on, off, or — where the choice is
/// mixed — a dash. Picking one puts it on everything chosen; picking it again takes it off.
@MainActor
private func tagsMenuItem(
    selection: ArchiveItemSelection,
    viewModel: ArchiveViewModel,
    isEnabled: Bool
) -> NSMenuItem {
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    let files = selection.files
    for tag in viewModel.tags {
        let carrying = files.filter { $0.tagIDs.contains(tag.id) }.count
        // Adding wins where the choice is mixed, as it does for Favorites.
        let isAdding = carrying < files.count
        let item = ActionMenuItem(title: tag.name, isEnabled: isEnabled) {
            guard selection.canTag, !viewModel.isOfflineMode else { return }
            Task { await viewModel.setTag(tag.id, on: files.map(\.id), isOn: isAdding) }
        }
        item.state = carrying == 0 ? .off : (carrying == files.count ? .on : .mixed)
        submenu.addItem(item)
    }
    if !viewModel.tags.isEmpty {
        submenu.addItem(.separator())
    }
    submenu.addItem(ActionMenuItem(title: String(localized: "New Tag…"), isEnabled: isEnabled) {
        guard selection.canTag, !viewModel.isOfflineMode else { return }
        viewModel.beginCreatingTag(assigningTo: files.map(\.id))
    })

    let item = NSMenuItem(title: String(localized: "Tags"), action: nil, keyEquivalent: "")
    item.submenu = submenu
    item.isEnabled = isEnabled
    return item
}
#endif
