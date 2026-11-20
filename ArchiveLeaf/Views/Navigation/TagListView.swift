import SwiftUI

#if !os(macOS)
/// The tags on the phone: what there is, how many files each holds, and a way to make one.
///
/// A tag opens the same file list a folder does — the tag says what a file is about, the folder
/// says where it sits, and both end in a list of files.
struct TagListView: View {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var path: [ArchiveRoute]
    /// Whether this pane carries its own title, as it does wherever it is the whole screen.
    var showsContentTitle = false
    /// What is open, kept where the folders keep it and keyed the way the Mac keys it.
    @State private var expansion = FolderExpansion()
    /// The tag being renamed, and the name being typed for it. Held here rather than in the view
    /// model: nothing outside this screen renames a tag on the phone.
    @State private var tagPathBeingRenamed: TagPathNode?
    @State private var newName = ""

    var body: some View {
        Group {
            if viewModel.tags.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        ContentUnavailableView(
                            "No Tags",
                            systemImage: "tag",
                            description: Text("A tag is added to a file from the file itself. Tags you add appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .refreshable { await viewModel.refresh() }
                }
            } else {
                List {
                    ArchiveTitledSection("Tags", isShowingContentTitle: showsContentTitle) {
                        ForEach(viewModel.tagTree) { node in
                            TagTreeRow(
                                node: node,
                                viewModel: viewModel,
                                expansion: expansion,
                                path: $path,
                                beginRenaming: beginRenaming
                            )
                        }
                    }
                }
            }
        }
        .archiveContentTitleChrome(showsContentTitle, barTitle: Text("Tags"))
        .refreshable { await viewModel.refresh() }
        .alert("Rename Tag", isPresented: renamingBinding) {
            TextField("Tag Name", text: $newName)
            Button("Cancel", role: .cancel) { tagPathBeingRenamed = nil }
            Button("Rename") {
                // Taken before the alert closes and clears it, as every other dialog here does.
                guard let node = tagPathBeingRenamed else { return }
                let name = newName
                tagPathBeingRenamed = nil
                Task { await viewModel.renameTagPath(at: node.id, to: name) }
            }
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { tagPathBeingRenamed != nil },
            set: { if !$0 { tagPathBeingRenamed = nil } }
        )
    }

    private func beginRenaming(_ node: TagPathNode) {
        newName = node.displayPath
        tagPathBeingRenamed = node
    }
}

/// One step of the tag tree, and the steps beneath it when it is open.
///
/// Every step can be entered, including the ones no tag was ever stored under: `Dev` exists because
/// `Dev/Xcode` does, and it gathers what its children gather. Only a step that is a tag of its own
/// can be renamed or deleted — there is nothing else to rename.
private struct TagTreeRow: View {
    let node: TagPathNode
    @Bindable var viewModel: ArchiveViewModel
    let expansion: FolderExpansion
    @Binding var path: [ArchiveRoute]
    let beginRenaming: (TagPathNode) -> Void
    var depth: Int = 0

    private var key: String { "tag-path:\(node.id)" }

    var body: some View {
        row
        if !node.children.isEmpty, expansion.isOpen(key: key) {
            ForEach(node.children) { child in
                AnyView(
                    TagTreeRow(
                        node: child,
                        viewModel: viewModel,
                        expansion: expansion,
                        path: $path,
                        beginRenaming: beginRenaming,
                        depth: depth + 1
                    )
                )
            }
        }
    }

    private var row: some View {
        Button {
            // Everything above it as well, exactly as the folder tree pushes a folder's ancestors:
            // a jump from the tree straight to something deep is what a tree is for, and the way
            // back out is then one level at a time rather than all the way to the top at once.
            path = viewModel.tagChain(to: node.id).map { ArchiveRoute.tag(path: $0.id) }
        } label: {
            ArchiveSourceRowLabel(
                name: node.name,
                systemImage: "tag",
                itemCount: node.itemCount,
                disclosure: node.children.isEmpty ? nil : expansion.binding(key: key),
                navigates: true
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Named the way a folder's row is named, so a test asks for the row rather than for the
        // words on it — which are wording, and translated.
        .accessibilityIdentifier("tag-row-\(node.name)")
        .padding(.leading, CGFloat(depth) * 16)
        // Renaming is the only row-level shortcut. Deleting stays in the contextual menu, where
        // its destructive meaning is explicit.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { beginRenaming(node) } label: {
                Label("Rename", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .tint(.accentColor)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { beginRenaming(node) }
            if let tag = node.tag {
                Button("Delete Tag", systemImage: "trash", role: .destructive) {
                    viewModel.tagPendingDeletion = tag
                }
            }
        }
    }
}
#endif
