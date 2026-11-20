import SwiftUI

#if !os(macOS)
/// What can be done to one item, wherever that item is met.
///
/// A folder, a tag and Favorites are three ways of reaching the same file, not three kinds of file.
/// So what a long press offers does not depend on which of them the reader came through: deciding
/// per screen what "probably isn't needed here" is how the same row came to offer three different
/// sets of commands.
///
/// The order is the order of the bar of actions and of the tabs — a place, a star, a tag, the Trash
/// last — with the two that only ever apply to a single thing, renaming and sharing, in between.
/// One row is one item, so everything here applies to exactly that item; what a mixed selection can
/// and cannot do is `ArchiveItemSelection`'s business, in the bar.
struct ArchiveItemMenu: View {
    let item: ArchiveItem
    @Bindable var viewModel: ArchiveViewModel

    var body: some View {
        if !viewModel.isOfflineMode {
            Button("Move To…", systemImage: "folder") { viewModel.beginMoving([item]) }

            if case .file(let file) = item {
                Button(
                    file.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: file.isFavorite ? "star.slash" : "star"
                ) {
                    Task { await viewModel.toggleFavorite(file.id) }
                }

                TagAssignmentMenu(files: [file], viewModel: viewModel)
            }

            Button("Rename", systemImage: "pencil") { viewModel.beginRenaming(item) }

            if case .file(let file) = item {
                // The sheet has nothing to point at, so it needs no anchor of its own.
                ShareLink(
                    item: ArchiveFileTransfer(file: file, exporter: viewModel.fileExporter),
                    preview: SharePreview(file.sidebarDisplayName)
                )
            }

            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                viewModel.itemsPendingTrash = [item]
            }
        }
    }
}
#endif
