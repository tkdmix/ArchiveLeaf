import SwiftUI

/// Naming a new tag. Nothing else to choose: a tag has no place in a hierarchy, which is the point
/// of it.
struct NewTagView: View {
    @Bindable var viewModel: ArchiveViewModel
    /// The sheet has one field and one reason to be open, so the keyboard is already where it
    /// needs to be.
    @FocusState private var isNaming: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Name", text: singleLineName)
                    .lineLimit(1)
                    .focused($isNaming)
                    .onSubmit { Task { await viewModel.createTagFromSheet() } }
            }
            .formStyle(.grouped)
            .navigationTitle("New Tag")
            .onAppear { isNaming = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isShowingNewTag = false }
                        .disabled(viewModel.isCreatingTag)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await viewModel.createTagFromSheet() }
                    }
                    .disabled(
                        viewModel.isCreatingTag
                            || viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320)
        #endif
    }

    /// `TextField` is visually one line, but pasted text can still place newline characters in
    /// its binding. A tag is a path-like name, never a note, so normalize pasted lines at entry.
    private var singleLineName: Binding<String> {
        Binding(
            get: { viewModel.newTagName },
            set: { value in
                viewModel.newTagName = value
                    .replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
            }
        )
    }
}
