import SwiftUI

/// The files carrying one tag.
///
/// The same list a folder shows, because it is the same list: choosing a tag rather than a folder
/// changes which files are gathered, not what can be done to them once they are.
struct TagContentsView: View {
    /// One step of the tag tree. Empty is the heading: everything carrying any tag.
    let path: String
    @Bindable var viewModel: ArchiveViewModel
    var onSelectFile: ((UUID) -> Void)?
    var onSelectTag: ((String) -> Void)?
    var selection: Binding<Set<UUID>> = .constant([])
    /// Selection mode belongs to the window's canonical browsing state; this list only projects it.
    var isSelectingItems: Binding<Bool> = .constant(false)
    /// Whether this pane carries its own title, as it does wherever it is the whole screen.
    var showsContentTitle = false
    /// This nested list is independently navigable on iOS and iPadOS, so it owns the same
    /// rename prompt as the top-level Tags tree.
    @State private var tagPathBeingRenamed: TagPathNode?
    @State private var fileBeingTagged: ArchiveFile?
    @State private var newName = ""

    init(
        path: String,
        viewModel: ArchiveViewModel,
        onSelectFile: ((UUID) -> Void)? = nil,
        onSelectTag: ((String) -> Void)? = nil,
        selection: Binding<Set<UUID>> = .constant([]),
        isSelectingItems: Binding<Bool> = .constant(false),
        showsContentTitle: Bool = false
    ) {
        self.path = path
        self.viewModel = viewModel
        self.onSelectFile = onSelectFile
        self.onSelectTag = onSelectTag
        self.selection = selection
        self.isSelectingItems = isSelectingItems
        self.showsContentTitle = showsContentTitle
    }

    private var name: String? { viewModel.tagNode(atPath: path)?.name }

    private var barTitleText: Text {
        if let name { return Text(verbatim: name) }
        return Text("Tags")
    }
    private var listedFiles: [ArchiveFile] { viewModel.files(taggedWithPath: path) }
    /// The steps directly beneath this one. They are rows here on every platform, the way the
    /// folders inside a folder are rows in the pane that folder opens: this pane shows one level,
    /// and these are the ways further in.
    private var childTags: [TagPathNode] {
        guard !path.isEmpty else { return viewModel.tagTree }
        return viewModel.tagNode(atPath: path)?.children ?? []
    }
    private var showsEmptyState: Bool { listedFiles.isEmpty && childTags.isEmpty }

    var body: some View {
        Group {
            if showsEmptyState {
                // The heading is the tree itself, so what is missing there is tags, not files.
                if path.isEmpty {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag",
                        description: Text("A tag is added to a file from the file itself. Tags you add appear here.")
                    )
                } else {
                    ContentUnavailableView(
                        "No Files",
                        systemImage: "tag",
                        description: Text("Files given this tag will appear here.")
                    )
                }
            } else {
                #if os(macOS)
                ArchiveItemTable(
                    items: listedFiles.map(ArchiveItem.file),
                    placeRows: childTags.map {
                        ArchivePlaceRow(id: $0.id, name: $0.name, symbolName: "tag")
                    },
                    viewModel: viewModel,
                    selection: selection,
                    onRename: { file, name in
                        Task { await viewModel.renameFile(id: file.id, to: name) }
                    },
                    commands: { _, table, row in
                        archiveFileCommands(
                            selected: listedFiles.filter { selection.wrappedValue.contains($0.id) },
                            viewModel: viewModel,
                            in: table,
                            row: row
                        )
                    },
                    onOpenPlace: { onSelectTag?($0.id) }
                )
                #else
                if isSelectingItems.wrappedValue {
                    List(selection: selection) {
                        ArchiveTitledSection(barTitleText, isShowingContentTitle: showsContentTitle) {
                            ForEach(listedFiles) { file in
                                ArchiveFileLabel(file: file, viewModel: viewModel).tag(file.id)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    List {
                        ArchiveTitledSection(barTitleText, isShowingContentTitle: showsContentTitle) {
                            ForEach(childTags) { child in
                                Button {
                                    onSelectTag?(child.id)
                                } label: {
                                    ArchiveSourceRowLabel(
                                        name: child.name,
                                        systemImage: "tag",
                                        itemCount: child.itemCount,
                                        disclosure: nil,
                                        navigates: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("tag-contents-row-\(child.name)")
                                // A child tag is still a tag, not a different kind of destination.
                                // Keep the one row-level action from the top-level tree here too.
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { beginRenaming(child) } label: {
                                        Label("Rename", systemImage: "pencil")
                                            .labelStyle(.iconOnly)
                                    }
                                    .tint(.accentColor)
                                }
                            }
                            ForEach(listedFiles) { file in
                                fileRow(file)
                                    .contextMenu {
                                        ArchiveItemMenu(item: .file(file), viewModel: viewModel)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button { fileBeingTagged = file } label: {
                                            Label("Tags", systemImage: "tag")
                                                .labelStyle(.iconOnly)
                                        }
                                        .tint(.indigo)
                                    }
                            }
                        }
                    }
                }
                #endif
            }
        }
        #if !os(macOS)
        .archiveSelectionBar(
            isSelecting: isSelectingItems,
            canSelect: !listedFiles.isEmpty
        ) { showsWords in
            ArchiveSelectionActions(
                selection: chosenItems,
                viewModel: viewModel,
                showsWords: showsWords
            )
        }
        #endif
        #if os(macOS)
        .navigationTitle(name ?? String(localized: "Tags"))
        #else
        .archiveContentTitleChrome(showsContentTitle, barTitle: barTitleText)
        #endif
        // The one thing there is to do to this list, as in Favorites — and the pane needs a
        // section of its own in the toolbar, or the document's controls slide off their pane.
        .toolbar { ArchiveSortMenu(viewModel: viewModel) }
        .refreshable { await viewModel.refresh() }
        #if !os(macOS)
        .alert("Rename Tag", isPresented: renamingBinding) {
            TextField("Tag Name", text: $newName)
            Button("Cancel", role: .cancel) { tagPathBeingRenamed = nil }
            Button("Rename") {
                guard let node = tagPathBeingRenamed else { return }
                let name = newName
                tagPathBeingRenamed = nil
                Task { await viewModel.renameTagPath(at: node.id, to: name) }
            }
        }
        .sheet(item: $fileBeingTagged) { file in
            TagAssignmentEditor(fileID: file.id, viewModel: viewModel)
        }
        #endif
    }

    /// What has been chosen, resolved against the very list on screen.
    private var chosenItems: ArchiveItemSelection {
        ArchiveItemSelection(
            items: listedFiles.filter { selection.wrappedValue.contains($0.id) }.map(ArchiveItem.file),
            requestedIDs: selection.wrappedValue
        )
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

    @ViewBuilder
    private func fileRow(_ file: ArchiveFile) -> some View {
        let label = ArchiveFileLabel(file: file, viewModel: viewModel)
        if let onSelectFile {
            Button { onSelectFile(file.id) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: ArchiveRoute.file(file.id)) { label }
        }
    }
}
