import SwiftUI

struct RenameArchiveItemView: View {
    @Bindable var viewModel: ArchiveViewModel

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $viewModel.renameDraft)
            }
            .formStyle(.grouped)
            .navigationTitle("Rename")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.itemBeingRenamed = nil }
                        .disabled(viewModel.isRenamingItem)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") { Task { await viewModel.renameItem() } }
                        .disabled(
                            viewModel.isRenamingItem
                                || viewModel.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .frame(minWidth: 320, minHeight: 140)
        .alert(
            "Item Could Not Be Renamed",
            isPresented: Binding(
                get: { viewModel.renameErrorMessage != nil },
                set: { if !$0 { viewModel.clearRenameError() } }
            )
        ) {
            Button("OK", action: viewModel.clearRenameError)
        } message: {
            Text(viewModel.renameErrorMessage ?? "Unknown error")
        }
    }
}
