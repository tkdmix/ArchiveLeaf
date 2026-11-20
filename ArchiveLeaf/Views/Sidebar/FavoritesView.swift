import SwiftUI

struct FavoritesView: View {
    @Bindable var viewModel: ArchiveViewModel
    var onSelectFile: ((UUID) -> Void)?
    var selection: Binding<Set<UUID>> = .constant([])
    /// Selection mode belongs to the window's canonical browsing state; this list only projects it.
    var isSelectingItems: Binding<Bool> = .constant(false)
    /// Whether this pane carries its own title, as it does wherever it is the whole screen.
    var showsContentTitle = false
    /// What was listed on arrival. Held for the length of the visit so that the list does not
    /// rearrange itself while it is being worked in.
    @State private var listedOnArrival: Set<UUID> = []

    init(
        viewModel: ArchiveViewModel,
        onSelectFile: ((UUID) -> Void)? = nil,
        selection: Binding<Set<UUID>> = .constant([]),
        isSelectingItems: Binding<Bool> = .constant(false),
        showsContentTitle: Bool = false
    ) {
        self.viewModel = viewModel
        self.onSelectFile = onSelectFile
        self.selection = selection
        self.isSelectingItems = isSelectingItems
        self.showsContentTitle = showsContentTitle
    }

    /// Favourites, plus whatever was here when the list was opened.
    ///
    /// Taking the star off removed the row at once, while the file itself stayed on screen beside
    /// the list it had just left. Rows now stay put until the user leaves Favourites and comes
    /// back: nothing acted on disappears from under the pointer, and nothing shifts underneath the
    /// next click either. The star on each row still says where it stands.
    private var listedFiles: [ArchiveFile] {
        let favorites = viewModel.favoriteFiles
        var listed = favorites
        let missing = listedOnArrival.subtracting(favorites.map(\.id))
        for id in missing {
            guard let file = viewModel.file(id: id) else { continue }
            let position = listed.firstIndex {
                $0.sidebarDisplayName
                    .localizedStandardCompare(file.sidebarDisplayName) == .orderedDescending
            }
            listed.insert(file, at: position ?? listed.endIndex)
        }
        return listed
    }

    private var listSelection: Binding<Set<UUID>> { selection }

    var body: some View {
        Group {
            if listedFiles.isEmpty {
                #if os(macOS)
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("Files added to Favorites will appear here.")
                )
                #else
                GeometryReader { geometry in
                    ScrollView {
                        ContentUnavailableView(
                            "No Favorites",
                            systemImage: "star",
                            description: Text("Files added to Favorites will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .refreshable { await viewModel.refresh() }
                }
                #endif
            } else {
                #if os(macOS)
                // The same list as a folder's, so that one file reads the same in both places.
                ArchiveItemTable(
                    items: listedFiles.map(ArchiveItem.file),
                    viewModel: viewModel,
                    selection: listSelection,
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
                    }
                )
                #else
                if isSelectingItems.wrappedValue {
                    // Selection is a distinct interaction state: rows are plain and tagged, so the
                    // system can pick several of them at once.
                    List(selection: listSelection) {
                        ArchiveTitledSection("Favorites", isShowingContentTitle: showsContentTitle) {
                            ForEach(listedFiles) { file in
                                ArchiveFileLabel(file: file, viewModel: viewModel).tag(file.id)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    List {
                        ArchiveTitledSection("Favorites", isShowingContentTitle: showsContentTitle) {
                            ForEach(listedFiles) { file in
                                fileRow(file)
                                    // The row remains in place for this visit after the star is removed,
                                    // matching the list's existing listedOnArrival behavior.
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            Task { await viewModel.toggleFavorite(file.id) }
                                        } label: {
                                            Label(
                                                file.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                                systemImage: file.isFavorite ? "star.slash" : "star"
                                            )
                                                .labelStyle(.iconOnly)
                                        }
                                        .tint(.orange)
                                    }
                                    .contextMenu {
                                        ArchiveItemMenu(item: .file(file), viewModel: viewModel)
                                    }
                            }
                        }
                    }
                }
                #endif
            }
        }
        .onAppear { listedOnArrival = Set(viewModel.favoriteFiles.map(\.id)) }
        #if !os(macOS)
        // The same bar of actions a folder's list carries. A file is the same file whichever list
        // it was reached through, so what can be done to several at once is the same too.
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
        .navigationTitle("Favorites")
        #else
        .archiveContentTitleChrome(showsContentTitle, barTitle: Text("Favorites"))
        #endif
        // Ordering is this list's own, and the only thing there is to do to it. Without a control
        // here the window's toolbar has no section over this pane at all, and the document's
        // controls slide off its own pane to the window's edge — so the same file read from
        // Favorites and from a folder would show its controls in two different places.
        .toolbar { ArchiveSortMenu(viewModel: viewModel) }
        .refreshable { await viewModel.refresh() }
        .alert(
            "Favorite Update Failed",
            isPresented: Binding(
                get: { viewModel.favoriteErrorMessage != nil },
                set: { if !$0 { viewModel.clearFavoriteError() } }
            )
        ) {
            Button("OK", action: viewModel.clearFavoriteError)
        } message: {
            Text(viewModel.favoriteErrorMessage ?? "Unknown error")
        }
    }

    /// What has been chosen, resolved against the very list on screen so that an id with no row
    /// makes the whole selection invalid rather than acting on part of it.
    private var chosenItems: ArchiveItemSelection {
        ArchiveItemSelection(
            items: listedFiles.filter { selection.wrappedValue.contains($0.id) }.map(ArchiveItem.file),
            requestedIDs: selection.wrappedValue
        )
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
