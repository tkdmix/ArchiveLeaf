import SwiftUI

struct NewFolderView: View {
    @Bindable var viewModel: ArchiveViewModel

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder Name", text: $viewModel.newFolderName)
                FolderDestinationPicker(
                    title: "Parent",
                    folders: viewModel.folders,
                    selection: $viewModel.newFolderParentID,
                    rootLabel: "Top of Folders"
                )
            }
            .formStyle(.grouped)
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isShowingNewFolder = false }
                        .disabled(viewModel.isCreatingFolder)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await viewModel.createFolder() }
                    }
                    .disabled(
                        viewModel.isCreatingFolder
                            || viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .frame(minWidth: 320, minHeight: 180)
        .alert(
            "Folder Could Not Be Created",
            isPresented: Binding(
                get: { viewModel.folderCreationErrorMessage != nil },
                set: { if !$0 { viewModel.clearFolderCreationError() } }
            )
        ) {
            Button("OK", action: viewModel.clearFolderCreationError)
        } message: {
            Text(viewModel.folderCreationErrorMessage ?? "Unknown error")
        }
    }
}
