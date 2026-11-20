import SwiftUI

/// The sheets and questions any pane can raise: making a folder, renaming, moving, throwing away.
///
/// Put on the window rather than on one pane, because more than one pane asks for them — a folder
/// is renamed from the folder pane while the file pane may be showing Favorites, and the pane that
/// was doing the presenting would not be on screen to present anything.
private struct ArchiveItemFlows: ViewModifier {
    @Bindable var viewModel: ArchiveViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Tag Could Not Be Saved",
                isPresented: Binding(
                    get: { viewModel.tagErrorMessage != nil },
                    set: { if !$0 { viewModel.clearTagError() } }
                )
            ) {
                Button("OK", action: viewModel.clearTagError)
            } message: {
                Text(viewModel.tagErrorMessage ?? "")
            }
            .sheet(isPresented: $viewModel.isShowingNewFolder) {
                NewFolderView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isShowingNewTag) {
                NewTagView(viewModel: viewModel)
            }
            .sheet(item: $viewModel.itemBeingRenamed) { _ in
                RenameArchiveItemView(viewModel: viewModel)
            }
            .sheet(
                isPresented: Binding(
                    get: { !viewModel.itemsBeingMoved.isEmpty },
                    set: { if !$0 { viewModel.itemsBeingMoved = [] } }
                )
            ) {
                MoveArchiveItemView(viewModel: viewModel)
            }
            // Asks first: a folder takes everything inside it out of view, and the row being
            // thrown away shows none of that.
            .archiveConfirmation(
                "Move this item to Trash?",
                presenting: $viewModel.itemsPendingTrash,
                confirmTitle: "Move to Trash"
            ) { items in
                Task { await viewModel.moveToTrash(items.map(\.id)) }
            }
            // A tag does not go to the Trash: there is nothing of the reader's inside it to get
            // back, only the grouping itself, so this asks once and is done.
            .archiveConfirmation(
                "Delete This Tag?",
                presenting: $viewModel.tagPendingDeletion,
                confirmTitle: "Delete Tag",
                message: { tag in
                    Text(
                        "“\(tag.name)” is removed from every file carrying it. The files themselves keep everything else."
                    )
                }
            ) { tag in
                Task { await viewModel.deleteTag(id: tag.id) }
            }
    }
}

extension View {
    func archiveItemFlows(viewModel: ArchiveViewModel) -> some View {
        modifier(ArchiveItemFlows(viewModel: viewModel))
    }
}
