import SwiftUI

/// Putting tags on files and taking them off, from wherever a file is listed.
///
/// One decision for everything chosen rather than one per file: adding wins where the choice is
/// mixed, the same way the star does. The mark on each row says where the choice stands — on for
/// all of them, a dash for some, nothing for none.
///
/// Every step of the tag tree is offered, not only the names something is already stored under.
/// `Dev` is a reasonable thing to put on a file even when the only tags so far are `Dev/Xcode/iOS`
/// and `Dev/Xcode/macOS` — the reader typed that word, and it is in front of them in the folder
/// pane. Choosing a step nothing carries yet stores it then.
struct TagAssignmentMenu: View {
    let files: [ArchiveFile]
    private var fileIDs: [UUID] { files.map(\.id) }
    @Bindable var viewModel: ArchiveViewModel

    private var offered: [TagPathNode] {
        viewModel.tagTree.flatMap(\.selfAndDescendants)
    }

    var body: some View {
        Menu {
            ForEach(offered) { node in
                let carrying = files.count { file in
                    node.tag.map { file.tagIDs.contains($0.id) } ?? false
                }
                Button {
                    Task {
                        await viewModel.setTag(
                            named: node.displayPath,
                            on: fileIDs,
                            isOn: carrying < files.count
                        )
                    }
                } label: {
                    Label(node.displayPath, systemImage: mark(carrying: carrying))
                }
            }
            if !offered.isEmpty {
                Divider()
            }
            Button("New Tag…", systemImage: "plus") {
                viewModel.beginCreatingTag(assigningTo: fileIDs)
            }
        } label: {
            Label("Tags", systemImage: "tag")
        }
    }

    private func mark(carrying: Int) -> String {
        if carrying == 0 { return "circle" }
        return carrying == files.count ? "checkmark.circle.fill" : "minus.circle"
    }
}

#if !os(macOS)
/// The full tag assignment surface opened from a file row's one swipe action.
///
/// A swipe begins one task — editing this file's tags — rather than choosing one tag as the
/// action itself.  Keep the editor open while several tags are changed so the whole assignment is
/// visible and can be corrected in one visit.
struct TagAssignmentEditor: View {
    let fileID: UUID
    @Bindable var viewModel: ArchiveViewModel
    @Environment(\.dismiss) private var dismiss

    private var offered: [TagPathNode] {
        viewModel.tagTree.flatMap(\.selfAndDescendants)
    }

    private var assignedTagIDs: Set<UUID> {
        Set(viewModel.file(id: fileID)?.tagIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(offered) { node in
                    Button {
                        Task {
                            await viewModel.setTag(
                                named: node.displayPath,
                                on: [fileID],
                                isOn: !isAssigned(node)
                            )
                        }
                    } label: {
                        Label(
                            node.displayPath,
                            systemImage: isAssigned(node) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Tag…", systemImage: "plus") {
                        dismiss()
                        Task { @MainActor in
                            await Task.yield()
                            viewModel.beginCreatingTag(assigningTo: [fileID])
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isAssigned(_ node: TagPathNode) -> Bool {
        node.tag.map { assignedTagIDs.contains($0.id) } ?? false
    }
}
#endif
