import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ArchiveFolderContentsView: View {
    let parentFolderID: UUID?
    @Bindable var viewModel: ArchiveViewModel
    var onSelectFile: ((UUID) -> Void)?
    /// Everything chosen here, which the window shows beside this pane and every command acts on.
    var selection: Binding<Set<UUID>> = .constant([])
    /// Selection mode belongs to the window's canonical browsing state. This view only projects
    /// it into the compact list's normal and selectable interaction states.
    var isSelectingItems: Binding<Bool> = .constant(false)
    /// False for Unsorted, which is not a folder: it is the files that are in none, so the
    /// folders at the top of the tree are not "inside" it and listing them here would copy the
    /// tree's first level into a place that means the opposite.
    var showsFolders = true
    /// The fixed-width iPad browser keeps its Folders titles in the scrolling list rather than
    /// consuming navigation-bar width needed by the list commands.
    var showsContentTitle = false
    /// The archive's own first level, which the Mac's middle pane shows when the folder heading is
    /// chosen: the folders at the top of the tree, with Unsorted among them exactly as the tree
    /// beside it lists them. It holds no files of its own — a file in no folder is in Unsorted, and
    /// that row is where it is listed, so listing it here as well would show it at two levels at
    /// once and make this pane the only one in the app showing two.
    var isArchiveRoot = false
    @State private var isShowingFileImporter = false
    /// How much room this pane has, used for the empty state and the Mac title.
    @State private var paneWidth: CGFloat = 0
    @State private var fileImporterError: String?
    /// Where this column has been pushed to. Held by whoever put the column on screen, not here:
    /// choosing a different place in the folder pane has to be able to empty it, and a stack this
    /// view kept to itself survived that choice and went on covering the new list.
    @Binding var path: [ArchiveRoute]

    init(
        parentFolderID: UUID?,
        viewModel: ArchiveViewModel,
        path: Binding<[ArchiveRoute]>,
        onSelectFile: ((UUID) -> Void)? = nil,
        selection: Binding<Set<UUID>> = .constant([]),
        isSelectingItems: Binding<Bool> = .constant(false),
        showsFolders: Bool = true,
        showsContentTitle: Bool = false,
        isArchiveRoot: Bool = false
    ) {
        self.parentFolderID = parentFolderID
        self.viewModel = viewModel
        _path = path
        self.onSelectFile = onSelectFile
        self.selection = selection
        self.isSelectingItems = isSelectingItems
        self.showsFolders = showsFolders
        self.showsContentTitle = showsContentTitle
        self.isArchiveRoot = isArchiveRoot
    }

    private var importButton: some View {
        Button("Import Files…", systemImage: "square.and.arrow.down") {
            isShowingFileImporter = true
        }
        .disabled(
            viewModel.isOfflineMode
                || viewModel.isInspectingImports
                || viewModel.isImporting
        )
    }

    private var reloadButton: some View {
        Button("Reload Archive", systemImage: "arrow.clockwise") {
            Task { await viewModel.refresh() }
        }
        .disabled(viewModel.isOfflineMode || viewModel.isRefreshing)
    }

    /// One button rather than a menu with one thing worth choosing in it. A bookmark arrives by
    /// being dropped in, like every other file; there is nothing to type into a form for it.
    private var newFolderButton: some View {
        Button("New Folder", systemImage: "folder.badge.plus") {
            viewModel.beginCreatingFolder(in: parentFolderID)
        }
        .disabled(viewModel.isOfflineMode)
    }

    /// Whether the name of what is being shown can sit beside the controls.
    private var hasRoomForTitle: Bool { paneWidth >= 260 }


    private var folders: [ArchiveFolder] {
        showsFolders ? viewModel.folders(in: parentFolderID) : []
    }
    private var files: [ArchiveFile] {
        isArchiveRoot ? [] : viewModel.files(in: parentFolderID)
    }

    /// Whether this pane has nothing to show. At the archive's own level the Unsorted row is there
    /// whether or not anything is in it, so emptiness is about what has come into the archive
    /// rather than about what this list draws: no folders at the top, and nothing in Unsorted.
    private var isEmpty: Bool {
        guard isArchiveRoot else { return folders.isEmpty && files.isEmpty }
        return folders.isEmpty && viewModel.files(in: nil).isEmpty
    }

    private var emptyNoticeTitle: LocalizedStringResource {
        if parentFolderID != nil { return "Folder Is Empty" }
        return showsFolders ? "Archive Is Empty" : "Unsorted Is Empty"
    }

    private var emptyNoticeDescription: LocalizedStringResource {
        if parentFolderID != nil { return "There are no items in this folder." }
        return showsFolders
            ? "Imported files will appear here."
            : "Files that are not in a folder will appear here."
    }

    /// A heading tells one kind of row from another, so it is worth its line only where both kinds
    /// are here. On the Mac, where folders have a pane of their own, this list is only ever files
    /// and "Files" said nothing — while Favorites and Trash, listing the same rows, carried no
    /// heading at all.
    #if !os(macOS)
    /// One list, the way a folder reads in the Finder and in Files: what is in this place, in one
    /// column. Two sections said that a folder and a file are different kinds of thing to be in a
    /// folder, which they are not.
    ///
    /// Folders come first in name order; files follow in whatever order the list is sorted by.
    /// Sorting by name backwards therefore turns the
    /// files around without letting one drift up among the folders.
    @ViewBuilder
    private var list: some View {
        if isSelectingItems.wrappedValue {
            selectingList
        } else {
            normalList
        }
    }

    /// Outside selection mode, rows keep their normal button and navigation behavior. Giving a
    /// List an empty selection binding here still made it consume the folder button's tap.
    private var normalList: some View {
        List {
            ArchiveTitledSection(title, isShowingContentTitle: showsContentTitle) {
                ForEach(folders) { folder in
                    NavigationLink(value: ArchiveRoute.folder(folder.id)) {
                        folderLabel(folder)
                    }
                    .contextMenu { ArchiveItemMenu(item: .folder(folder), viewModel: viewModel) }
                    // Asks first: a folder takes everything inside it out of view, and the row
                    // being swiped shows none of that.
                    .trashSwipeAction(isEnabled: !viewModel.isOfflineMode) {
                        viewModel.itemsPendingTrash = [.folder(folder)]
                    }
                }

                ForEach(files) { file in
                    fileRow(file)
                        .contextMenu { ArchiveItemMenu(item: .file(file), viewModel: viewModel) }
                        // Files follow the same confirmation path as folders: the compact swipe
                        // does not make a different safety promise just because the item is a file.
                        .trashSwipeAction(isEnabled: !viewModel.isOfflineMode) {
                            viewModel.itemsPendingTrash = [.file(file)]
                        }
                }
            }
        }
    }

    /// Selection is a distinct interaction state: both folders and files are plain, tagged rows
    /// in one list so the system can select them together.
    private var selectingList: some View {
        List(selection: selection) {
            ArchiveTitledSection(title, isShowingContentTitle: showsContentTitle) {
                ForEach(folders) { folder in
                    folderLabel(folder)
                        .tag(folder.id)
                }

                ForEach(files) { file in
                    fileRow(file)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    /// What has been chosen, resolved against the very list on screen so that an id with no row
    /// makes the whole selection invalid rather than acting on part of it.
    private var chosenItems: ArchiveItemSelection {
        let items = folders.map(ArchiveItem.folder) + files.map(ArchiveItem.file)
        return ArchiveItemSelection(
            items: items.filter { selection.wrappedValue.contains($0.id) },
            requestedIDs: selection.wrappedValue
        )
    }

    /// No chevron of its own. The row is a link, and a link in a list already draws one — on iOS 26
    /// the two showed up side by side. The tree's rows still draw theirs, because those are buttons
    /// rather than links and nothing else would say they go anywhere.
    private func folderLabel(_ folder: ArchiveFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .contentShape(.rect)
    }
    #endif

    #if os(macOS)
    private var fileTable: some View {
        let items = folders.map(ArchiveItem.folder) + files.map(ArchiveItem.file)
        return ArchiveItemTable(
            items: items,
            placeRows: placeRows,
            viewModel: viewModel,
            selection: selection,
            onRename: renameFile,
            onImport: { urls in
                Task { await viewModel.inspectExternalDrop(at: urls, into: parentFolderID) }
            },
            commands: { _, table, row in
                archiveFileCommands(
                    selection: ArchiveItemSelection(
                        items: items.filter { selection.wrappedValue.contains($0.id) },
                        requestedIDs: selection.wrappedValue
                    ),
                    viewModel: viewModel,
                    in: table,
                    row: row
                )
            },
            onOpen: { item in
                guard case .folder(let folder) = item else { return }
                path.append(.folder(folder.id))
            },
            onOpenPlace: { _ in path.append(.unsorted) }
        )
    }

    /// What this pane lists that is not an item: Unsorted, at the archive's first level. First
    /// among the folders and staying there, exactly as the tree beside this pane lists it — every
    /// file is under some folder, and the ones nobody has filed are under this one.
    private var placeRows: [ArchivePlaceRow] {
        guard isArchiveRoot else { return [] }
        return [
            ArchivePlaceRow(
                id: "unsorted",
                name: String(localized: "Unsorted Files"),
                symbolName: "tray"
            ),
        ]
    }


    private func renameFile(_ file: ArchiveFile, to name: String) {
        Task { await viewModel.renameFile(id: file.id, to: name) }
    }
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            fileTable
            #else
            list
            #endif
        }
        .measuringPaneWidth(into: $paneWidth)
        #if !os(macOS)
        // Which of the actions are offered is decided by `ArchiveItemSelection`, the same judgement
        // the Mac's menu asks — a folder carries neither a tag nor a star, so those two go quiet
        // the moment one is included.
        .archiveSelectionBar(
            isSelecting: isSelectingItems,
            canSelect: !(folders.isEmpty && files.isEmpty)
        ) { showsWords in
            ArchiveSelectionActions(
                selection: chosenItems,
                viewModel: viewModel,
                showsWords: showsWords
            )
        }
        #endif
        .overlay {
            if isEmpty {
                PaneNotice(
                    emptyNoticeTitle,
                    systemImage: parentFolderID == nil ? "archivebox" : "folder",
                    description: emptyNoticeDescription,
                    width: paneWidth
                ) {
                    AnyView(importButton)
                }
            }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await viewModel.inspectExternalDrop(at: urls, into: parentFolderID) }
            return true
        }
        .focusedValue(\.inspectFilesAction) {
            guard !viewModel.isInspectingImports && !viewModel.isImporting else { return }
            isShowingFileImporter = true
        }
        #endif
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.inspectImports(at: urls, into: parentFolderID) }
            case .failure(let error):
                fileImporterError = error.localizedDescription
            }
        }
        .alert(
            "Could Not Select Files",
            isPresented: Binding(
                get: { fileImporterError != nil },
                set: { if !$0 { fileImporterError = nil } }
            )
        ) {
            Button("OK") { fileImporterError = nil }
        } message: {
            Text(fileImporterError ?? "Unknown error")
        }
        #if os(macOS)
        .navigationTitle(title)
        #else
        .archiveContentTitleChrome(showsContentTitle, barTitle: title)
        #endif
        #if os(macOS)
        // Dropped rather than forced, and taken out altogether rather than emptied: the slot it
        // sits in is about 170 points wide and keeps that room whether or not there is a word in
        // it, which is what pushed this pane's controls over the divider. The pane is for its list,
        // and the tree beside it already says where this is.
        .modifier(TitleShownWhenThereIsRoom(hasRoom: hasRoomForTitle))
        #endif
        // CloudKit is the source of truth and answers from an index that trails its own writes, so
        // an automatic refresh can still miss something just added. This is the recourse.
        .refreshable { await viewModel.refresh() }
        .toolbar {
            #if os(macOS)
            // Acting on the archive: intake first as the most frequent, then making and ordering.
            // The Mac adapts this pane's commands to its measured split width.
            if paneWidth >= 380 {
                ToolbarItemGroup {
                    importButton

                    newFolderButton
                }

                #if os(macOS)
                // Pull to refresh is the shared touch idiom. The Mac also keeps its explicit
                // command, including Command-R, because there is no equivalent pull gesture.
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }

                ToolbarItemGroup {
                    reloadButton
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
                #endif

                ToolbarItemGroup {
                    ArchiveSortMenu(viewModel: viewModel)
                }
            } else {
                // Pushed to this pane's trailing edge, where its controls sit when there is room
                // for all of them. Without the title there is nothing else holding that side.
                if #available(macOS 26.0, iOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                }

                // Bringing files in is what this pane is for, so it stays. The rest is a press
                // further away rather than pushing the pane wider than the reader wants it.
                ToolbarItemGroup {
                    importButton

                    Menu("More", systemImage: "ellipsis") {
                        newFolderButton

                        #if os(macOS)
                        reloadButton

                        Divider()
                        #endif

                        ArchiveSortMenu(viewModel: viewModel)
                    }
                }
            }
            #else
            // Keep the mobile controls flat and independently declared, in priority order. The
            // system owns spacing and overflow; this view never groups, hides, or substitutes
            // archive commands based on its measured width.
            ToolbarItem(placement: .topBarTrailing) {
                importButton
            }
            if showsFolders {
                ToolbarItem(placement: .topBarTrailing) {
                    newFolderButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ArchiveSortMenu(viewModel: viewModel)
            }
            #endif
        }

        .alert(
            "Archive Operation Failed",
            isPresented: Binding(
                get: {
                    viewModel.trashErrorMessage != nil
                        || viewModel.favoriteErrorMessage != nil
                        || viewModel.moveErrorMessage != nil
                },
                set: { if !$0 { clearOperationErrors() } }
            )
        ) {
            Button("OK", action: clearOperationErrors)
        } message: {
            Text(
                viewModel.trashErrorMessage
                    ?? viewModel.favoriteErrorMessage
                    ?? viewModel.moveErrorMessage
                    ?? "Unknown error"
            )
        }
    }

    private var title: Text {
        if let name = parentFolderID.flatMap({ viewModel.folder(id: $0)?.name }) {
            Text(verbatim: name)
        } else if isArchiveRoot {
            // The archive's first level, which the tree beside it calls by the same name.
            Text("Folders")
        } else {
            // The files that belong to no folder. The folder pane calls this row the same thing.
            Text("Unsorted Files")
        }
    }

    @ViewBuilder
    private func fileRow(_ file: ArchiveFile) -> some View {
        let label = ArchiveFileLabel(file: file, viewModel: viewModel)
        #if !os(macOS)
        if isSelectingItems.wrappedValue {
            label.tag(file.id)
        } else if let onSelectFile {
            Button { onSelectFile(file.id) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: ArchiveRoute.file(file.id)) { label }
        }
        #else
        if onSelectFile != nil {
            label.tag(file.id)
        } else {
            NavigationLink(value: ArchiveRoute.file(file.id)) { label }
        }
        #endif
    }

    private func clearOperationErrors() {
        viewModel.clearTrashError()
        viewModel.clearFavoriteError()
        viewModel.clearMoveError()
    }

}

/// A content-owned title starts at the top of its pane. The system's normal scroll-content
/// margin is intended to make room for a navigation title, which this presentation deliberately
/// does not use.
private extension View {
    /// Trailing edge only. A leading swipe collides with the system's sidebar gesture on iPad.
    /// Moving an item to Trash always asks for confirmation and never supports a full swipe.
    func trashSwipeAction(
        isEnabled: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEnabled {
                Button(role: .destructive, action: perform) {
                    Label("Move to Trash", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }
}
