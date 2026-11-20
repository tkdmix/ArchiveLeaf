import SwiftUI

struct MoveArchiveItemView: View {
    @Bindable var viewModel: ArchiveViewModel

    var body: some View {
        NavigationStack {
            Form {
                FolderDestinationPicker(
                    title: "Move To",
                    folders: viewModel.availableMoveDestinationFolders,
                    selection: $viewModel.moveDestinationFolderID,
                    rootLabel: viewModel.itemsBeingMoved.allSatisfy(\.isFolder)
                        ? "Top of Folders"
                        : "Unsorted Files"
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Move Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.itemsBeingMoved = [] }
                        .disabled(viewModel.isMovingItem)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { await viewModel.moveItem() } }
                        .disabled(viewModel.isMovingItem)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 160)
        .alert(
            "Item Could Not Be Moved",
            isPresented: Binding(
                get: { viewModel.moveErrorMessage != nil },
                set: { if !$0 { viewModel.clearMoveError() } }
            )
        ) {
            Button("OK", action: viewModel.clearMoveError)
        } message: {
            Text(viewModel.moveErrorMessage ?? "Unknown error")
        }
    }
}
