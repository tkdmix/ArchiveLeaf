import Foundation
import Observation

enum ArchiveLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case iCloudUnavailable
    case failed(String)
}

@MainActor
@Observable
final class ArchiveViewModel {
    private static let sortModeDefaultsKey = "ArchiveLeaf.archiveSortMode"
    private static let sortAscendingDefaultsKey = "ArchiveLeaf.archiveSortAscending"

    /// Compatibility state for operations that need a current item, such as the default macOS
    /// import destination. Navigation paths and split-view selection own presentation state.
    var selection: ArchiveItem?

    /// The page on screen, where the system browser shows it.
    ///
    /// Held here rather than in the pane that asked for it, for the same reason `RootView` holds
    /// where the reader is: on iPad the two layouts replace each other whenever the window changes
    /// shape — including for a moment while switching apps — and state inside one of them does not
    /// survive that. Kept there, the page closed itself on the way back from the Home screen.
    ///
    /// A page covers the whole app, so this is also simply where it belongs: nothing about it is
    /// the pane's business. macOS is the exception and keeps its browser in the pane, because there
    /// the browser *is* pane content.
    var openPage: URL?

    /// The file the reader has just chosen and not yet been shown.
    ///
    /// Choosing a bookmark opens its page, and only choosing does. Restoring where the reader was
    /// must not, or launching the app would land inside a browser they never asked for this time;
    /// deriving the page from the focused file alone cannot tell those two apart, because the
    /// focused file is the same either way. So the act is recorded here rather than inferred, and
    /// it is deliberately not part of `ArchiveBrowsingState`: that value is written to disk, and
    /// an intention from the last run is not an intention.
    ///
    /// Recorded for every file, not only bookmarks, so that whoever notes the choice does not have
    /// to know the format. Only a bookmark's page has anywhere to go with it.
    private(set) var chosenFileID: UUID?

    /// Notes that the reader chose this file. Called wherever a file becomes the focused one by
    /// someone pressing it — including a press on the file already focused, which is how a reader
    /// asks for its page a second time.
    func noteFileChosen(_ id: UUID) {
        chosenFileID = id
    }

    /// Takes the choice if it was this file's, leaving nothing behind for a later appearance of the
    /// same file to act on.
    func takeChoice(of id: UUID) -> Bool {
        guard chosenFileID == id else { return false }
        chosenFileID = nil
        return true
    }

    var sortAscending: Bool {
        didSet { defaults.set(sortAscending, forKey: Self.sortAscendingDefaultsKey) }
    }

    var sortMode: ArchiveSortMode {
        didSet { defaults.set(sortMode.rawValue, forKey: Self.sortModeDefaultsKey) }
    }
    private(set) var folders: [ArchiveFolder] = [] {
        didSet { index = ArchiveIndex(files: files, folders: folders) }
    }
    private(set) var files: [ArchiveFile] = [] {
        didSet { index = ArchiveIndex(files: files, folders: folders) }
    }
    /// The same archive, arranged for the questions the lists ask. Rebuilt when the archive changes
    /// — which is rare — rather than walked again for every row of every redraw, which is not.
    private var index = ArchiveIndex()
    /// Names to sort files by. A folder says where a file is; a tag says what it is about, and one
    /// file can carry several.
    ///
    /// Always in name order. CloudKit answers a query in whatever order it likes, so the order is
    /// put on here rather than trusted from the read — the list came back shuffled, and differently
    /// each time.
    private(set) var tags: [ArchiveTag] = [] {
        didSet {
            let ordered = tags.sorted { nameOrder($0.name, $1.name) }
            if ordered.map(\.id) != tags.map(\.id) { tags = ordered }
        }
    }
    private(set) var tagErrorMessage: String?
    var isShowingNewTag = false
    var newTagName = ""
    private(set) var isCreatingTag = false
    var tagPendingDeletion: ArchiveTag?
    /// Files waiting for the tag being named. A tag made from a file's own menu is made in order
    /// to put it on that file; making it and then having to go and apply it is two steps for one
    /// intention.
    private var filesAwaitingNewTag: [UUID] = []
    private(set) var loadState: ArchiveLoadState = .idle
    private(set) var isRefreshing = false
    /// Whether the archive has ever been read, which tells a first read from a later one.
    private var hasLoadedArchive = false
    private var lastRefreshedAt = Date.distantPast
    private(set) var isOfflineMode = false
    private(set) var offlineOperationMessage: String?
    private(set) var isInspectingImports = false
    private(set) var isImporting = false
    private(set) var importErrorMessage: String?
    var importDestinationFolderID: UUID?
    var isShowingNewFolder = false
    var newFolderName = ""
    var newFolderParentID: UUID?
    private(set) var isCreatingFolder = false
    private(set) var folderCreationErrorMessage: String?
    var itemBeingRenamed: ArchiveItem?
    /// What sits inside each trashed folder, so its row can say what a restore brings back.
    var trashedFolderItemCounts: [UUID: Int] = [:]
    var renameDraft = ""
    private(set) var isRenamingItem = false
    private(set) var renameErrorMessage: String?
    /// What the move sheet is about. Several, since several can be chosen.
    var itemsBeingMoved: [ArchiveItem] = []
    var moveDestinationFolderID: UUID?
    private(set) var isMovingItem = false
    private(set) var moveErrorMessage: String?
    private(set) var trashedFiles: [ArchiveFile] = []
    private(set) var trashedFolders: [ArchiveFolder] = []
    private(set) var isLoadingTrash = false
    /// Whether the Trash has ever been read, which is what tells a first visit from a return.
    private var hasLoadedTrash = false
    private(set) var trashErrorMessage: String?
    private(set) var trashResultMessage: String?
    private(set) var favoriteErrorMessage: String?
    private(set) var displayFormatErrorMessage: String?
    private(set) var sourceEncodingErrorMessage: String?
    /// What the Trash question is about. Several, since several can be chosen.
    var itemsPendingTrash: [ArchiveItem] = []
    private var cachedTrashedSubtrees: [UUID: ArchiveSnapshot] = [:]
    private(set) var importPreflightResult: ImportPreflightResult?
    private(set) var importResult: ImportResult?
    private var securityScopedImportURLs: [URL] = []

    private let repository: any ArchiveRepository
    private let importPreflight: any ImportPreflightChecking
    private let archiveImporter: any ArchiveImporting
    private let contentLoader: any FileContentLoading
    /// Reachable without the main actor, which is what a share sheet needs.
    nonisolated let fileExporter: ArchiveFileExporter
    private let thumbnailLoader: any FileThumbnailLoading
    private let archiveCache: (any ArchiveCaching)?
    private let snapshotCache: (any ArchiveSnapshotCaching)?
    private let connectivity: any ConnectivityChecking
    private let importDate: @Sendable () -> Date
    /// Where the sorting choices are kept. Given rather than reached for, so that a test changing
    /// one does not change it for every other test in the process.
    private let defaults: UserDefaults

    init(
        repository: any ArchiveRepository,
        importPreflight: any ImportPreflightChecking = ImportPreflightService(),
        archiveImporter: (any ArchiveImporting)? = nil,
        contentLoader: (any FileContentLoading)? = nil,
        thumbnailLoader: (any FileThumbnailLoading)? = nil,
        archiveCache: (any ArchiveCaching)? = nil,
        snapshotCache: (any ArchiveSnapshotCaching)? = nil,
        connectivity: any ConnectivityChecking = AlwaysOnlineConnectivity(),
        importDate: @escaping @Sendable () -> Date = { .now },
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        sortMode = ArchiveSortMode(
            rawValue: defaults.string(forKey: Self.sortModeDefaultsKey) ?? ""
        ) ?? .displayName
        sortAscending = defaults.object(forKey: Self.sortAscendingDefaultsKey) as? Bool ?? true
        self.repository = repository
        self.importPreflight = importPreflight
        self.archiveImporter = archiveImporter ?? ArchiveImportService(repository: repository)
        self.archiveCache = archiveCache
        self.snapshotCache = snapshotCache
        self.connectivity = connectivity
        let resolvedContentLoader = contentLoader ?? RepositoryFileContentLoader(
            repository: repository,
            cache: archiveCache
        )
        self.contentLoader = resolvedContentLoader
        self.fileExporter = ArchiveFileExporter(contentLoader: resolvedContentLoader)
        self.thumbnailLoader = thumbnailLoader ?? FileThumbnailLoader(
            contentLoader: resolvedContentLoader,
            cache: archiveCache
        )
        self.importDate = importDate
    }

    func loadThumbnail(for file: ArchiveFile) async throws -> Data? {
        try await thumbnailLoader.loadThumbnail(for: file)
    }

    /// Reads the archive.
    ///
    /// Only the first read empties the panes to wait. Later ones — after an import, say — keep what
    /// is on screen, because blanking the folder tree to say "loading" takes away the thing the
    /// reader is looking at to tell them about something happening elsewhere.
    func load() async {
        if !hasLoadedArchive {
            loadState = .loading
        }
        defer { hasLoadedArchive = true }
        // A read is a read: without this, returning to the app moments after launch read the whole
        // archive a second time, and the second one spun in the file pane long after the folder
        // pane had finished.
        defer { lastRefreshedAt = .now }

        do {
            // Read with the rest of it, and now in the same breath. The Trash is the same archive
            // from the same place: leaving it out moved its wait to whenever it was first opened,
            // and asking for it separately fetched every record a second and third time to arrive
            // at what this read already holds.
            let contents = try await repository.fetchContents()
            let snapshot = contents.snapshot
            try? await snapshotCache?.storeSnapshot(snapshot)
            folders = snapshot.folders
            files = snapshot.files
            tags = snapshot.tags
            adoptTrash(contents)
            isOfflineMode = false
            loadState = folders.isEmpty && files.isEmpty ? .empty : .loaded
        } catch where !connectivity.isOnline() {
            if let snapshot = try? await snapshotCache?.loadSnapshot() {
                folders = snapshot.folders
                files = snapshot.files
                tags = snapshot.tags
                isOfflineMode = true
                loadState = folders.isEmpty && files.isEmpty ? .empty : .loaded
            } else {
                folders = []
                files = []
                selection = nil
                isOfflineMode = true
                loadState = .failed("No downloaded archive metadata is available. Connect to the internet and try again.")
            }
        } catch CloudKitRepositoryError.iCloudUnavailable {
            folders = []
            files = []
            selection = nil
            loadState = .iCloudUnavailable
        } catch {
            folders = []
            files = []
            selection = nil
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Re-reads the archive without clearing what is on screen.
    ///
    /// Unlike `load()`, this keeps the current contents visible while it works and leaves them
    /// alone on failure: it runs when the user did not ask to wait — returning to the app, or
    /// pulling to refresh — so blanking the screen would be a worse answer than a stale one.
    /// Reads the archive again.
    ///
    /// Nothing tells this app that another device has changed something — there is no subscription
    /// to CloudKit's changes — so the archive is only as current as the last time it was read.
    func refresh() async {
        guard connectivity.isOnline() else { return }
        isRefreshing = true
        defer { lastRefreshedAt = .now }
        do {
            let contents = try await repository.fetchContents()
            let snapshot = contents.snapshot
            try? await snapshotCache?.storeSnapshot(snapshot)
            folders = snapshot.folders
            files = snapshot.files
            tags = snapshot.tags
            adoptTrash(contents)
            isOfflineMode = false
            loadState = snapshot.folders.isEmpty && snapshot.files.isEmpty ? .empty : .loaded
            // The wait is over here: what the reader was looking at has been answered. The Trash
            // used to be a second errand whose spinner made a finished read look like a stuck one;
            // it now arrives with the first.
            isRefreshing = false
        } catch {
            isRefreshing = false
            // Left as it was. A failed refresh is not news the user asked for.
        }
    }

    func refreshConnectivity() async {
        if connectivity.isOnline() {
            if isOfflineMode {
                await load()
            } else {
                try? await snapshotCache?.storeSnapshot(currentSnapshot)
            }
        } else {
            let shouldRetryOfflineLoad: Bool
            switch loadState {
            case .failed, .iCloudUnavailable:
                shouldRetryOfflineLoad = !isOfflineMode
            default:
                shouldRetryOfflineLoad = false
            }
            isOfflineMode = true
            if shouldRetryOfflineLoad {
                await load()
            }
        }
    }

    func clearOfflineOperationMessage() { offlineOperationMessage = nil }

    /// Adopts the archive that a reset or restore just produced.
    ///
    /// Deliberately does not re-read from the repository. CloudKit serves queries from an index
    /// that trails its own writes, so a read here returned an archive missing the file the restore
    /// had written moments earlier. The caller performed those writes and knows the outcome.
    func adoptReplacedArchive(_ snapshot: ArchiveSnapshot) async {
        selection = nil
        trashedFiles = []
        trashedFolders = []
        // What is in the Trash of an archive just replaced is not known until it is read, so the
        // next visit waits rather than claiming it is empty.
        hasLoadedTrash = false
        trashErrorMessage = nil
        itemsPendingTrash = []
        cachedTrashedSubtrees.removeAll()
        folders = snapshot.folders
        files = snapshot.files
        tags = snapshot.tags
        isOfflineMode = false
        loadState = snapshot.folders.isEmpty && snapshot.files.isEmpty ? .empty : .loaded
        try? await snapshotCache?.storeSnapshot(snapshot)
    }

    func files(in folder: ArchiveFolder) -> [ArchiveFile] {
        sortedFiles(parentFolderID: folder.id)
    }

    /// How many rows opening this folder shows: the folders in it, and the files in it.
    ///
    /// **The number beside any row is the number of rows that row opens onto.** One sentence for
    /// every place in the pane, and one that can be checked by counting what is on screen.
    ///
    /// Counting everything underneath instead was tried and was worse in the reader's own archive:
    /// a folder holding one folder and no files of its own showed the child's number, which it had
    /// borrowed, and a folder showing 4 opened onto two files. A file sits in exactly one place, so
    /// the total is a real quantity — but it is not what this row is about, and opening the folder
    /// is what answers it.
    ///
    /// `nil` is Unsorted: the files in no folder at all. The folders at the top of the tree are not
    /// inside it, so they are not counted here.
    func itemCount(inFolderWithID parentFolderID: UUID?) -> Int {
        index.itemCount(inFolderWithID: parentFolderID)
    }

    /// The folders from the top of the tree down to this one, ending with it.
    ///
    /// Pushed as a whole when a folder is chosen from the tree, so that going back steps up one
    /// level at a time — and the system's own back button names the parent — while still allowing
    /// a jump straight to somewhere deep.
    func folderChain(to folderID: UUID) -> [ArchiveFolder] {
        var chain: [ArchiveFolder] = []
        var current: UUID? = folderID
        var visited = Set<UUID>()
        while let id = current, visited.insert(id).inserted, let folder = folder(id: id) {
            chain.append(folder)
            current = folder.parentFolderID
        }
        return chain.reversed()
    }

    func folders(in parentFolderID: UUID?) -> [ArchiveFolder] {
        sortedFolders(parentFolderID: parentFolderID)
    }

    func files(in parentFolderID: UUID?) -> [ArchiveFile] {
        sortedFiles(parentFolderID: parentFolderID)
    }

    func folder(id: UUID) -> ArchiveFolder? {
        index.foldersByID[id]
    }

    func file(id: UUID) -> ArchiveFile? {
        index.filesByID[id]
    }

    var rootFiles: [ArchiveFile] {
        sortedFiles(parentFolderID: nil)
    }

    /// Ordered the way every other list is, so that the choice made in one place holds in this one.
    var favoriteFiles: [ArchiveFile] {
        sorted(index.favorites, by: sortMode)
    }

    /// - Parameter destinationFolderID: the folder the files land in, or nil for the archive root.
    ///   Always passed explicitly: deriving it from `selection` looked right but read a value that
    ///   navigation never sets and that folder operations change as a side effect, so the window
    ///   toolbar's destination depended on the last edit rather than on what was on screen.
    /// Brings files in, where the caller says they go.
    ///
    /// Nothing is asked first. Every way in already knows the destination — the folder dropped on,
    /// the folder being shown, the one the share sheet writes to — so a sheet asking again was in
    /// the way of the only thing the reader wanted, and it could not even make a folder to answer
    /// with. What it did that mattered is kept: anything refused is reported afterwards, by name
    /// and with the reason.
    func inspectImports(at urls: [URL], into destinationFolderID: UUID?) async {
        guard requireOnline() else { return }
        removeTemporaryImportDirectories()
        stopAccessingImportURLs()
        isInspectingImports = true
        importResult = nil
        importDestinationFolderID = destinationFolderID
        securityScopedImportURLs = urls.filter { $0.startAccessingSecurityScopedResource() }

        let preflight = await importPreflight.inspect(urls: urls)
        importPreflightResult = preflight
        isInspectingImports = false

        await importCandidates(preflight.candidates)
        reportRefusedImports()
        finishImport()
    }

    /// Turns web addresses into the same immutable `.webloc` assets as direct entry, while file
    /// URLs continue down the ordinary import path. No page is fetched merely because its address
    /// was dragged into the shelf.
    func inspectExternalDrop(at urls: [URL], into destinationFolderID: UUID?) async {
        guard requireOnline(), !urls.isEmpty else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeaf-Drop-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            var usedNames = Set(files.filter {
                $0.parentFolderID == destinationFolderID && !$0.isTrashed
            }.map(\.displayName))
            let importURLs = try urls.map { url in
                if url.isFileURL, url.pathExtension.lowercased() != "webloc" { return url }
                let webURL = url.isFileURL
                    ? try BookmarkDocument.url(from: Data(contentsOf: url))
                    : url
                let itemDirectory = directory.appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: itemDirectory,
                    withIntermediateDirectories: false
                )
                let title = BookmarkDocument.uniqueTitle(for: webURL, among: usedNames)
                usedNames.insert(title)
                return try BookmarkDocument.write(url: webURL, title: title, into: itemDirectory)
            }
            await inspectImports(at: importURLs, into: destinationFolderID)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    /// What did not come in, and why. Silence would leave the reader believing everything did.
    ///
    /// From the import where there was something to import, and from the inspection where there
    /// was not: dropping a single unusable file goes nowhere near the importer, and said nothing
    /// at all until this looked in both places.
    private func reportRefusedImports() {
        let refused = importResult?.failures ?? importPreflightResult?.failures ?? []
        guard !refused.isEmpty else { return }
        importErrorMessage = refused
            .map { "\($0.sourceURL.lastPathComponent): \($0.reason)" }
            .joined(separator: "\n")
    }

    func importCandidates(_ candidates: [ImportCandidate]) async {
        guard requireOnline() else { return }
        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }

        let requestedFolderPaths = importPreflightResult?.folderPathComponents ?? []
        guard !candidates.isEmpty || !requestedFolderPaths.isEmpty else { return }

        var importedFiles: [ArchiveFile] = []
        // What inspection already refused, carried through rather than used as a reason to refuse
        // the rest. One file the archive already holds used to stop everything selected with it.
        var failures: [ImportFailure] = importPreflightResult?.failures ?? []
        let importFolders: [ArchiveFolder]
        let destinationFolderIDs: [String: UUID?]

        do {
            let plan = try makeImportFolderPlan(
                candidates: candidates,
                requestedFolderPaths: requestedFolderPaths
            )
            importFolders = plan.folders
            destinationFolderIDs = plan.destinationFolderIDs
            // Parents before children, in the order the plan built them, and written together.
            try await repository.create(folders: importFolders)
        } catch {
            importErrorMessage = error.localizedDescription
            return
        }

        // Per parent, because files no longer all land in one freshly created folder. Worked out
        // for the whole import before anything is written, so the write itself is one piece of work.
        var placements: [ImportPlacement] = []
        for candidate in candidates {
            let parentPath = normalizedFolderPath(Array(candidate.importPathComponents.dropLast()))
            guard let destinationFolderID = destinationFolderIDs[parentPath] else {
                failures.append(ImportFailure(
                    sourceURL: candidate.sourceURL,
                    reason: ImportBatchValidationError.invalidRelativePath.localizedDescription
                ))
                continue
            }
            placements.append(ImportPlacement(candidate: candidate, folderID: destinationFolderID))
        }
        let outcome = await archiveImporter.importFiles(placements)
        importedFiles = outcome.importedFiles
        failures.append(contentsOf: outcome.failures)

        importResult = ImportResult(
            importedFiles: importedFiles,
            createdFolders: importFolders,
            failures: failures
        )
        removeTemporaryImportDirectories()
        // What came in is known here — it was just written — so the archive is not read again to
        // find it out. That read was three queries over the whole archive, and it could not be
        // relied on to show the new files anyway: CloudKit answers a query from an index that has
        // not necessarily caught up, which is why they were appended by hand afterwards regardless.
        // Nothing else an import touches needs re-reading: no tag is created and the Trash is
        // untouched.
        folders += importFolders.filter { new in !folders.contains { $0.id == new.id } }
        files += importedFiles.filter { new in !files.contains { $0.id == new.id } }
        try? await snapshotCache?.storeSnapshot(
            ArchiveSnapshot(folders: folders, files: files, tags: tags)
        )
        loadState = .loaded
        selection = importedFiles.last.map(ArchiveItem.file)
            ?? importFolders.first.map(ArchiveItem.folder)
    }

    private func finishImport() {
        removeTemporaryImportDirectories()
        stopAccessingImportURLs()
        importPreflightResult = nil
        importResult = nil
    }

    func clearImportError() {
        importErrorMessage = nil
    }

    func loadContent(for file: ArchiveFile) async throws -> LoadedFileContent {
        do {
            return try await contentLoader.loadContent(for: file)
        } catch where isOfflineMode || !connectivity.isOnline() {
            isOfflineMode = true
            throw OfflineArchiveError.contentNotDownloaded
        }
    }

    func beginCreatingFolder(in parentFolderID: UUID?) {
        guard requireOnline() else { return }
        newFolderName = ""
        newFolderParentID = parentFolderID
        folderCreationErrorMessage = nil
        isShowingNewFolder = true
    }

    func createFolder() async {
        guard requireOnline() else { return }
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreatingFolder = true
        folderCreationErrorMessage = nil
        defer { isCreatingFolder = false }

        let folder = ArchiveFolder(
            name: trimmedName,
            parentFolderID: newFolderParentID
        )

        do {
            try ArchiveTreeValidator.validate(
                folder: folder,
                in: ArchiveSnapshot(folders: folders, files: files)
            )
            try await repository.save(folder: folder)
            folders.append(folder)
            loadState = .loaded
            selection = .folder(folder)
            isShowingNewFolder = false
        } catch {
            folderCreationErrorMessage = error.localizedDescription
        }
    }

    func clearFolderCreationError() {
        folderCreationErrorMessage = nil
    }

    func beginRenaming(_ item: ArchiveItem) {
        guard requireOnline() else { return }
        itemBeingRenamed = item
        renameDraft = item.displayName
        renameErrorMessage = nil
    }

    func renameItem() async {
        guard requireOnline() else { return }
        guard let item = itemBeingRenamed else { return }
        let trimmedName = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenamingItem = true
        renameErrorMessage = nil
        defer { isRenamingItem = false }

        do {
            let updatedItem: ArchiveItem
            switch item {
            case .folder(var folder):
                folder.name = trimmedName
                folder.updatedAt = .now
                try ArchiveTreeValidator.validate(folder: folder, in: currentSnapshot)
                try await repository.save(folder: folder)
                replace(folder)
                updatedItem = .folder(folder)
            case .file(var file):
                file.userDefinedName = trimmedName
                file.updatedAt = .now
                try ArchiveTreeValidator.validate(file: file, in: currentSnapshot)
                try await repository.save(file: file)
                replace(file)
                updatedItem = .file(file)
            }
            selection = updatedItem
            itemBeingRenamed = nil
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    /// Renames a file outright, for a list that edits the name in its own row.
    ///
    /// The same validation as the sheet's: a name that clashes with a sibling is refused before
    /// anything is written, and the row is left as it was.
    /// Renames a folder outright, for a tree that edits the name in its own row.
    func renameFolder(id: UUID, to name: String) async {
        guard requireOnline(), let folder = folder(id: id) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != folder.name else { return }
        renameErrorMessage = nil
        do {
            var updatedFolder = folder
            updatedFolder.name = trimmedName
            updatedFolder.updatedAt = .now
            try ArchiveTreeValidator.validate(folder: updatedFolder, in: currentSnapshot)
            try await repository.save(folder: updatedFolder)
            replace(updatedFolder)
            if selection?.id == updatedFolder.id {
                selection = .folder(updatedFolder)
            }
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    func renameFile(id: UUID, to name: String) async {
        guard requireOnline(), let file = file(id: id) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != file.displayName else { return }
        renameErrorMessage = nil
        do {
            var updatedFile = file
            updatedFile.userDefinedName = trimmedName
            updatedFile.updatedAt = .now
            try ArchiveTreeValidator.validate(file: updatedFile, in: currentSnapshot)
            try await repository.save(file: updatedFile)
            replace(updatedFile)
            if selection?.id == updatedFile.id {
                selection = .file(updatedFile)
            }
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }

    func beginMoving(_ items: [ArchiveItem]) {
        guard requireOnline(), let first = items.first else { return }
        itemsBeingMoved = items
        // Where they are now, which is the answer for the common case of moving them together.
        moveDestinationFolderID = first.parentFolderID
        moveErrorMessage = nil
    }

    func moveItem() async {
        guard requireOnline() else { return }
        let items = itemsBeingMoved
        guard !items.isEmpty else { return }
        isMovingItem = true
        moveErrorMessage = nil
        defer { isMovingItem = false }

        // One at a time, stopping at the first refusal so that what has moved is what was allowed
        // to move, and the reason is the reason for the one that stopped.
        for item in items {
            guard await move(item) else { return }
        }
        itemsBeingMoved = []
    }

    private func move(_ item: ArchiveItem) async -> Bool {
        do {
            let updatedItem: ArchiveItem
            switch item {
            case .folder(var folder):
                folder.parentFolderID = moveDestinationFolderID
                folder.updatedAt = .now
                try ArchiveTreeValidator.validate(folder: folder, in: currentSnapshot)
                try await repository.save(folder: folder)
                replace(folder)
                updatedItem = .folder(folder)
            case .file(var file):
                file.parentFolderID = moveDestinationFolderID
                file.updatedAt = .now
                try ArchiveTreeValidator.validate(file: file, in: currentSnapshot)
                try await repository.save(file: file)
                replace(file)
                updatedItem = .file(file)
            }
            selection = updatedItem
            return true
        } catch {
            moveErrorMessage = error.localizedDescription
            return false
        }
    }

    var availableMoveDestinationFolders: [ArchiveFolder] {
        let movingFolderIDs = itemsBeingMoved.compactMap { item -> UUID? in
            guard case .folder(let folder) = item else { return nil }
            return folder.id
        }
        return folders.filter { candidate in
            !movingFolderIDs.contains { isDescendant(candidate.id, of: $0) }
        }
    }

    func clearRenameError() { renameErrorMessage = nil }
    func clearMoveError() { moveErrorMessage = nil }

    /// Only the first time is worth waiting for.
    ///
    /// The Trash is read again every time it is opened, because it can be added to from another
    /// device. Emptying the pane while that happens meant a spinner on every visit, for a list that
    /// was already known and rarely changes. What was last read stays on screen, and is replaced
    /// when the new answer arrives.
    /// Reads the archive again unless it was read a moment ago.
    ///
    /// For coming back to the app. On the Mac that happens every time the reader switches to
    /// another app and back, which is often; a fetch each time would be paid for nothing. Long
    /// enough away, and something may well have arrived from the phone.
    func refreshIfStale() async {
        guard Date.now.timeIntervalSince(lastRefreshedAt) > 30 else { return }
        await refresh()
    }

    func loadTrash() async {
        guard requireOnline() else { return }
        isLoadingTrash = !hasLoadedTrash
        trashErrorMessage = nil
        defer { isLoadingTrash = false }
        do {
            adoptTrash(try await repository.fetchContents())
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    /// The Trash half of a read the archive half has already taken.
    ///
    /// Whoever read the archive read the Trash with it, so this only ever puts down what has
    /// arrived. Marking it read here is what stops the Trash spinning on its first visit for
    /// something a launch already fetched.
    private func adoptTrash(_ contents: ArchiveContents) {
        trashedFiles = contents.trashedFiles
        trashedFolders = contents.trashedFolders
        trashedFolderItemCounts = contents.trashedFolderItemCounts
        hasLoadedTrash = true
    }

    /// Everything chosen, in one write where it can be.
    ///
    /// Files are the bulk of any selection and all a file needs is its own record changed, so they
    /// go together. A folder takes its whole subtree out of view and has a snapshot kept for the
    /// way back, so folders keep the path written for one at a time — there are rarely many, and
    /// what they each do is not the same work twice.
    func moveToTrash(_ ids: [UUID]) async {
        guard requireOnline() else { return }
        itemsPendingTrash = []
        let items = ids.compactMap(archiveItem(id:))
        let chosenFiles = items.compactMap { item -> ArchiveFile? in
            guard case .file(let file) = item else { return nil }
            return file
        }
        await moveFilesToTrash(chosenFiles)
        for item in items {
            guard case .folder(let folder) = item else { continue }
            await moveToTrash(folder.id)
        }
    }

    /// The file half of the above: one write for all of them, and one rearranging of the lists.
    private func moveFilesToTrash(_ chosen: [ArchiveFile]) async {
        guard !chosen.isEmpty else { return }
        let discarded = chosen.map { original -> ArchiveFile in
            var file = original
            file.originalParentFolderID = file.parentFolderID
            file.isTrashed = true
            file.trashedAt = .now
            file.updatedAt = .now
            return file
        }

        do {
            let failures = try await repository.save(files: discarded)
            let moved = discarded.filter { failures[$0.id] == nil }
            let movedIDs = Set(moved.map(\.id))
            files.removeAll { movedIDs.contains($0.id) }
            trashedFiles.removeAll { movedIDs.contains($0.id) }
            // Newest first, which is the one rule the Trash has.
            trashedFiles.insert(contentsOf: moved.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }, at: 0)
            if let selection, movedIDs.contains(selection.id) { self.selection = nil }
            loadState = folders.isEmpty && files.isEmpty ? .empty : .loaded
            if !failures.isEmpty {
                trashErrorMessage = bulkFailureMessage(
                    failures,
                    of: discarded.count,
                    verb: String(localized: "move to Trash")
                )
            }
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    /// By id, not by a copy of the item.
    ///
    /// The row a command came from can be older than the thing it stands for — built before a tag
    /// was put on, or the star pressed — and writing that copy back quietly undoes the difference.
    /// Taking only the id makes that impossible to write.
    func moveToTrash(_ id: UUID) async {
        guard requireOnline() else { return }
        itemsPendingTrash = []
        guard let item = archiveItem(id: id) else { return }
        do {
            var shouldClearSelection = selection?.id == item.id
            switch item {
            case .file(var file):
                file.originalParentFolderID = file.parentFolderID
                file.isTrashed = true
                file.trashedAt = .now
                file.updatedAt = .now
                try await repository.save(file: file)
                files.removeAll { $0.id == file.id }
                trashedFiles.removeAll { $0.id == file.id }
                trashedFiles.insert(file, at: 0)
            case .folder(var folder):
                let subtreeIDs = ArchiveTrashFilter.subtreeFolderIDs(
                    rootedAt: [folder.id],
                    folders: folders
                )
                cachedTrashedSubtrees[folder.id] = ArchiveSnapshot(
                    folders: folders.filter { subtreeIDs.contains($0.id) },
                    files: files.filter { $0.parentFolderID.map(subtreeIDs.contains) ?? false }
                )
                folder.originalParentFolderID = folder.parentFolderID
                folder.isTrashed = true
                folder.trashedAt = .now
                folder.updatedAt = .now
                try await repository.save(folder: folder)
                if let selection {
                    switch selection {
                    case .folder(let selectedFolder):
                        shouldClearSelection = subtreeIDs.contains(selectedFolder.id)
                    case .file(let selectedFile):
                        shouldClearSelection = selectedFile.parentFolderID.map(subtreeIDs.contains) ?? false
                    }
                }
                folders.removeAll { subtreeIDs.contains($0.id) }
                files.removeAll { $0.parentFolderID.map(subtreeIDs.contains) ?? false }
                trashedFolders.removeAll { $0.id == folder.id }
                trashedFolders.insert(folder, at: 0)
            }
            if shouldClearSelection { selection = nil }
            loadState = folders.isEmpty && files.isEmpty ? .empty : .loaded
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    /// Everything chosen, brought back in one write where it can be.
    ///
    /// Working out where a file goes back to costs nothing — the folder it came from if it is still
    /// there, `Recovered Items` if it is not, and a name that does not collide with what is already
    /// in that folder. All of that is decided here, in order, so that two files coming back to the
    /// same folder still get different names, and only then is the whole set written.
    func restore(_ items: [ArchiveItem]) async {
        guard requireOnline() else { return }
        let chosenFiles = items.compactMap { item -> ArchiveFile? in
            guard case .file(let file) = item else { return nil }
            return file
        }
        await restoreFiles(chosenFiles)
        for item in items {
            guard case .folder(let folder) = item else { continue }
            await restore(folder)
        }
    }

    private func restoreFiles(_ chosen: [ArchiveFile]) async {
        guard !chosen.isEmpty else { return }
        var restored: [ArchiveFile] = []
        do {
            for trashedFile in chosen {
                var file = trashedFile
                let destinationID = try await restoredParentID(file.originalParentFolderID)
                file.parentFolderID = destinationID
                file.originalParentFolderID = nil
                file.isTrashed = false
                file.trashedAt = nil
                file.userDefinedName = availableRestoredName(for: file, in: destinationID)
                file.updatedAt = .now
                try ArchiveTreeValidator.validate(file: file, in: currentSnapshot)
                // Put in place as we go, so the next file coming back to the same folder is named
                // against this one rather than against the archive as it was a moment ago.
                restored.append(file)
                files.append(file)
                trashedFiles.removeAll { $0.id == file.id }
            }

            let failures = try await repository.save(files: restored)
            guard !failures.isEmpty else {
                loadState = .loaded
                if let last = restored.last { selection = .file(last) }
                return
            }
            // What the server refused goes back into the Trash, where it still is.
            for file in restored where failures[file.id] != nil {
                files.removeAll { $0.id == file.id }
                if let original = chosen.first(where: { $0.id == file.id }) {
                    trashedFiles.insert(original, at: 0)
                }
            }
            loadState = folders.isEmpty && files.isEmpty ? .empty : .loaded
            trashErrorMessage = bulkFailureMessage(
                failures,
                of: restored.count,
                verb: String(localized: "restore")
            )
        } catch {
            // Nothing was written yet: put the lists back the way they were.
            let stagedIDs = Set(restored.map(\.id))
            files.removeAll { stagedIDs.contains($0.id) }
            for file in chosen where stagedIDs.contains(file.id) {
                trashedFiles.insert(file, at: 0)
            }
            trashErrorMessage = error.localizedDescription
        }
    }

    func restore(_ trashedFile: ArchiveFile) async {
        guard requireOnline() else { return }
        var file = trashedFile
        do {
            let destinationID = try await restoredParentID(file.originalParentFolderID)

            file.parentFolderID = destinationID
            file.originalParentFolderID = nil
            file.isTrashed = false
            file.trashedAt = nil
            file.userDefinedName = availableRestoredName(for: file, in: destinationID)
            file.updatedAt = .now
            try ArchiveTreeValidator.validate(file: file, in: currentSnapshot)
            try await repository.save(file: file)

            trashedFiles.removeAll { $0.id == file.id }
            files.append(file)
            loadState = .loaded
            selection = .file(file)
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    func restore(_ trashedFolder: ArchiveFolder) async {
        guard requireOnline() else { return }
        var folder = trashedFolder
        do {
            let destinationID = try await restoredParentID(folder.originalParentFolderID)
            folder.parentFolderID = destinationID
            folder.originalParentFolderID = nil
            folder.isTrashed = false
            folder.trashedAt = nil
            folder.updatedAt = .now

            let cachedSubtree = cachedTrashedSubtrees[folder.id]
            let descendantFolders = cachedSubtree?.folders.filter { $0.id != folder.id } ?? []
            let validationSnapshot = ArchiveSnapshot(
                folders: folders + [folder] + descendantFolders,
                files: files + (cachedSubtree?.files ?? [])
            )
            try ArchiveTreeValidator.validate(folder: folder, in: validationSnapshot)
            try await repository.save(folder: folder)

            trashedFolders.removeAll { $0.id == folder.id }
            if let cachedSubtree {
                folders.append(folder)
                folders.append(contentsOf: descendantFolders.filter { descendant in
                    !folders.contains(where: { $0.id == descendant.id })
                })
                files.append(contentsOf: cachedSubtree.files.filter { descendant in
                    !files.contains(where: { $0.id == descendant.id })
                })
                cachedTrashedSubtrees[folder.id] = nil
            } else {
                for _ in 0..<5 {
                    await load()
                    if folders.contains(where: { $0.id == folder.id }) { break }
                    try await Task.sleep(for: .seconds(1))
                }
                if !folders.contains(where: { $0.id == folder.id }) {
                    folders.append(folder)
                }
            }
            loadState = .loaded
            selection = .folder(folder)
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    func clearTrashError() { trashErrorMessage = nil }

    /// The tags on what a permanent delete is about to take, including everything under a folder.
    ///
    /// A folder's descendants are what the subtree cache holds when the Trash has been opened on
    /// it; without that, the files still on hand are the best this device can say. Anything missed
    /// leaves a name behind, which is the harmless direction.
    private func tagIDsCarried(by item: ArchiveItem) -> Set<UUID> {
        switch item {
        case .file(let file):
            return Set(file.tagIDs)
        case .folder(let folder):
            let subtreeFiles = cachedTrashedSubtrees[folder.id]?.files
                ?? trashedFiles.filter { $0.parentFolderID == folder.id }
            return Set(subtreeFiles.flatMap(\.tagIDs))
        }
    }

    func permanentlyDelete(_ item: ArchiveItem) async {
        guard requireOnline() else { return }
        trashErrorMessage = nil
        trashResultMessage = nil
        // Read before the delete, because afterwards the thing that carried them is gone.
        let carriedTagIDs = tagIDsCarried(by: item)
        do {
            let result = try await repository.permanentlyDelete(item)
            try? await archiveCache?.removeAll()
            if selection?.id == item.id { selection = nil }
            // Dropped locally rather than re-read. CloudKit answers queries from an index that
            // trails its own writes, so asking again here returned records still marked untrashed
            // and emptied the whole list — everything looked deleted.
            switch item {
            case .file:
                trashedFiles.removeAll { $0.id == item.id }
            case .folder:
                trashedFolders.removeAll { $0.id == item.id }
                cachedTrashedSubtrees[item.id] = nil
            }
            trashResultMessage = "Permanently deleted \(result.deletedItemCount) items."
            // What was deleted may have been the last thing carrying one of its own tags.
            await pruneEmptyTags(among: carriedTagIDs)
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    func emptyTrash() async {
        guard requireOnline() else { return }
        trashErrorMessage = nil
        trashResultMessage = nil
        let carriedTagIDs = Set(trashedFiles.flatMap(\.tagIDs))
        do {
            let result = try await repository.emptyTrash()
            try? await archiveCache?.removeAll()
            // Emptied locally for the same reason: the result is known, and a query would answer
            // from an index that has not caught up.
            trashedFiles = []
            trashedFolders = []
            cachedTrashedSubtrees.removeAll()
            trashResultMessage = "Permanently deleted \(result.deletedItemCount) items."
            await pruneEmptyTags(among: carriedTagIDs)
        } catch {
            trashErrorMessage = error.localizedDescription
        }
    }

    func clearTrashResult() { trashResultMessage = nil }

    func toggleFavorite(_ id: UUID) async {
        guard requireOnline() else { return }
        // By id: tapping faster than the view redraws would otherwise turn the star on twice from
        // the same starting point.
        guard let file = self.file(id: id) else { return }
        var updatedFile = file
        updatedFile.isFavorite.toggle()
        updatedFile.updatedAt = .now
        favoriteErrorMessage = nil

        // Shown before the write, and put back if it fails. Favouriting is a single tap and the
        // answer is already known; waiting for CloudKit to agree made the tap look ignored.
        replace(updatedFile)
        if selection?.id == updatedFile.id {
            selection = .file(updatedFile)
        }

        do {
            try await repository.save(file: updatedFile)
        } catch {
            replace(file)
            if selection?.id == file.id {
                selection = .file(file)
            }
            favoriteErrorMessage = error.localizedDescription
        }
    }

    /// Puts the star on, or takes it off, for many files at once, leaving alone the ones already
    /// that way. One decision for the whole set: dropping ten files onto Favorites means marking
    /// them, not turning off the two that were already marked.
    ///
    /// One write for the whole selection rather than one per file, and one redraw rather than one
    /// per file — the list used to fill in a star at a time, at a round trip each, because that is
    /// what a loop of single saves looks like from the outside.
    ///
    /// What the server refuses is put back the way it was and named in the error. The rest stands:
    /// a selection is a list of separate intentions, and nineteen of them are not undone by the
    /// twentieth.
    func setFavorite(_ isFavorite: Bool, on fileIDs: [UUID]) async {
        guard requireOnline() else { return }
        let originals = fileIDs.compactMap(file(id:)).filter { $0.isFavorite != isFavorite }
        guard !originals.isEmpty else { return }
        favoriteErrorMessage = nil

        let updated = originals.map { original -> ArchiveFile in
            var file = original
            file.isFavorite = isFavorite
            file.updatedAt = .now
            return file
        }
        // Shown before the write, as a single tap has always been: the answer is known, and the
        // list should not fill itself in one row at a time while the network agrees.
        apply(updated)

        do {
            let failures = try await repository.save(files: updated)
            guard !failures.isEmpty else { return }
            apply(originals.filter { failures[$0.id] != nil })
            favoriteErrorMessage = bulkFailureMessage(
                failures,
                of: updated.count,
                verb: String(localized: "favorite")
            )
        } catch {
            apply(originals)
            favoriteErrorMessage = error.localizedDescription
        }
    }

    /// Replaces several files at once, and keeps whatever is on screen beside the list in step.
    private func apply(_ files: [ArchiveFile]) {
        for file in files {
            replace(file)
            if selection?.id == file.id {
                selection = .file(file)
            }
        }
    }

    /// Says how many did not make it and why, rather than showing one file's error as if it were
    /// the whole story.
    private func bulkFailureMessage(
        _ failures: [UUID: any Error],
        of attempted: Int,
        verb: String
    ) -> String {
        let reason = failures.values.first?.localizedDescription ?? ""
        if failures.count == attempted {
            return reason
        }
        return String(
            localized: "\(failures.count) of \(attempted) items could not be saved. \(reason)"
        )
    }

    func clearFavoriteError() { favoriteErrorMessage = nil }

    func setDisplayFormat(_ format: ImportedFormat?, for file: ArchiveFile) async {
        guard requireOnline() else { return }
        guard file.displayFormatOverride != format else { return }
        var updatedFile = file
        updatedFile.displayFormatOverride = format
        updatedFile.updatedAt = .now
        displayFormatErrorMessage = nil

        do {
            try await repository.save(file: updatedFile)
            replace(updatedFile)
            if selection?.id == updatedFile.id {
                selection = .file(updatedFile)
            }
        } catch {
            displayFormatErrorMessage = error.localizedDescription
        }
    }

    func clearDisplayFormatError() { displayFormatErrorMessage = nil }

    func setSourceEncoding(_ encoding: ArchiveTextEncoding?, for file: ArchiveFile) async {
        guard requireOnline() else { return }
        guard file.sourceEncodingOverride != encoding else { return }
        var updatedFile = file
        updatedFile.sourceEncodingOverride = encoding
        updatedFile.updatedAt = .now
        sourceEncodingErrorMessage = nil

        do {
            try await repository.save(file: updatedFile)
            replace(updatedFile)
            if selection?.id == updatedFile.id {
                selection = .file(updatedFile)
            }
        } catch {
            sourceEncodingErrorMessage = error.localizedDescription
        }
    }

    func clearSourceEncodingError() { sourceEncodingErrorMessage = nil }

    func move(itemWithID draggedID: UUID, into destinationID: UUID?) async {
        guard requireOnline() else { return }
        guard let item = archiveItem(id: draggedID), item.id != destinationID else { return }
        moveErrorMessage = nil
        do {
            try await move(item, to: destinationID)
        } catch {
            moveErrorMessage = error.localizedDescription
        }
    }

    func handleInternalDrop(
        draggedID: UUID,
        onto target: ArchiveItem,
        moveIntoFolder: Bool
    ) async {
        guard requireOnline() else { return }
        guard let draggedItem = archiveItem(id: draggedID), draggedItem.id != target.id else { return }
        // Only into a folder. A file dropped on a file used to change the order by hand; that order
        // is gone, so there is nothing such a drop could mean.
        guard moveIntoFolder, case .folder(let destination) = target else { return }
        moveErrorMessage = nil
        do {
            try await move(draggedItem, to: destination.id)
        } catch {
            moveErrorMessage = error.localizedDescription
        }
    }

    private func move(_ item: ArchiveItem, to destinationID: UUID?) async throws {
        switch item {
        case .folder(var folder):
            folder.parentFolderID = destinationID
            folder.updatedAt = .now
            try ArchiveTreeValidator.validate(folder: folder, in: currentSnapshot)
            try await repository.save(folder: folder)
            replace(folder)
            selection = .folder(folder)
        case .file(var file):
            file.parentFolderID = destinationID
            file.updatedAt = .now
            try ArchiveTreeValidator.validate(file: file, in: currentSnapshot)
            try await repository.save(file: file)
            replace(file)
            selection = .file(file)
        }
    }

    func archiveItem(id: UUID) -> ArchiveItem? {
        if let folder = folders.first(where: { $0.id == id }) { return .folder(folder) }
        if let file = files.first(where: { $0.id == id }) { return .file(file) }
        return nil
    }

    // MARK: - Tags

    /// The files carrying a tag, in the same order the same files take in a folder.
    ///
    /// Sorted through the one sorting the file list uses, because this is the file list: choosing
    /// a tag rather than a folder changes which files are gathered, not how they are shown.
    /// The tags as the panes draw them: one row per step of a slash-separated name.
    var tagTree: [TagPathNode] {
        TagPathNode.tree(tags: tags, files: files)
    }

    /// The files given this step's own name, and not those of the steps beneath it.
    ///
    /// Addressed by path rather than by tag, because half the rows in that tree are not tags:
    /// `Dev` exists because `Dev/Xcode/iOS` does, and nothing was ever stored under that name. Such
    /// a row showed a count and refused to be chosen; it now opens onto the steps under it and has
    /// no files of its own. An empty path is the heading the tags hang from, which is the tree
    /// itself rather than a place holding files.
    ///
    /// Descendants used to be gathered here, which made a tag the one pane in the archive that
    /// showed what was not at the level it was showing: `Dev/Xcode` listed the files of
    /// `Dev/Xcode/macOS`, while a folder never lists the files of the folders inside it. One rule
    /// for both — a pane shows the steps at this level and the files at this level — is what the
    /// reader can carry from one area to the other.
    func files(taggedWithPath path: String) -> [ArchiveFile] {
        guard let tag = tag(atPath: path) else { return [] }
        return sorted(index.files(carryingAnyOf: [tag.id]), by: sortMode)
    }

    /// Puts a tag on files by name, storing that name if this is the first file to carry it.
    ///
    /// A step of the tag tree can be chosen before anything is stored under it: `Dev` is a row in
    /// the folder pane because `Dev/Xcode/iOS` is a tag, and putting `Dev` on a file is what makes
    /// `Dev` a tag as well. Taking one off asks for nothing to be made — there is nothing to take
    /// off a name nothing carries.
    func setTag(named name: String, on fileIDs: [UUID], isOn: Bool) async {
        guard isOn else {
            guard let tag = tag(atPath: TagPathNode.foldedKey(name)) else { return }
            await setTag(tag.id, on: fileIDs, isOn: false)
            return
        }
        guard let tag = await createTag(named: name) else { return }
        await setTag(tag.id, on: fileIDs, isOn: true)
    }

    /// The tag stored under a path, where one is. A path assembled out of other tags' names has
    /// none, which is what tells a row that can be renamed and deleted from one that can only be
    /// read.
    func tag(atPath path: String) -> ArchiveTag? {
        tags.first { TagPathNode.foldedKey($0.name) == path }
    }

    /// The steps of the tag tree from the top down to this one, ending with it.
    ///
    /// The folders' own chain, for the tags: pushed as a whole so that going back steps up one
    /// level at a time. Walked through the tree rather than split on slashes, because a name a
    /// older build allowed — `Dev//iOS` — is one row, not three.
    func tagChain(to path: String) -> [TagPathNode] {
        func search(_ nodes: [TagPathNode], above: [TagPathNode]) -> [TagPathNode]? {
            for node in nodes {
                let chain = above + [node]
                if node.id == path { return chain }
                if let found = search(node.children, above: chain) { return found }
            }
            return nil
        }
        return search(tagTree, above: []) ?? []
    }

    /// The row at a path, for its name as it was typed rather than as it is matched.
    func tagNode(atPath path: String) -> TagPathNode? {
        func search(_ nodes: [TagPathNode]) -> TagPathNode? {
            for node in nodes {
                if node.id == path { return node }
                if let found = search(node.children) { return found }
            }
            return nil
        }
        return search(tagTree)
    }

    func tag(id: UUID) -> ArchiveTag? {
        tags.first { $0.id == id }
    }

    func tags(on file: ArchiveFile) -> [ArchiveTag] {
        file.tagIDs.compactMap(tag(id:)).sorted { nameOrder($0.name, $1.name) }
    }

    /// Adds a tag, or returns the one already carrying that name.
    ///
    /// Two tags of the same name would read as one thing and filter as two, so the name is what
    /// identifies a tag to the reader even though an id identifies it to the archive.
    @discardableResult
    func createTag(named name: String) async -> ArchiveTag? {
        guard requireOnline() else { return nil }
        guard let trimmedName = TagPathNode.normalizedName(name) else {
            tagErrorMessage = String(localized: "Separate tag levels with a single slash, with a name on both sides.")
            return nil
        }
        if let existing = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return existing
        }
        tagErrorMessage = nil
        let tag = ArchiveTag(name: trimmedName)
        do {
            try await repository.save(tag: tag)
            tags.append(tag)
            return tag
        } catch {
            tagErrorMessage = error.localizedDescription
            return nil
        }
    }

    func renameTag(id: UUID, to name: String) async {
        guard requireOnline(), let tag = tag(id: id) else { return }
        guard let trimmedName = TagPathNode.normalizedName(name) else {
            tagErrorMessage = String(localized: "Separate tag levels with a single slash, with a name on both sides.")
            return
        }
        guard trimmedName != tag.name else { return }
        guard !tags.contains(where: {
            $0.id != tag.id && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) else {
            tagErrorMessage = "A tag named “\(trimmedName)” already exists."
            return
        }
        tagErrorMessage = nil
        var updatedTag = tag
        updatedTag.name = trimmedName
        updatedTag.updatedAt = .now
        do {
            try await repository.save(tag: updatedTag)
            replace(updatedTag)
        } catch {
            tagErrorMessage = error.localizedDescription
        }
    }

    /// Renames one visible step of the presentation tree and every stored tag beneath it.
    ///
    /// Intermediate rows such as `Dev/Xcode` need not be stored tags themselves. Renaming that
    /// row therefore means changing the same path prefix on `Dev/Xcode/iOS`,
    /// `Dev/Xcode/macOS`, and any other descendants. Every destination is validated before the
    /// first save so a collision cannot deliberately leave a half-renamed subtree.
    func renameTagPath(at path: String, to name: String) async {
        guard requireOnline(), let node = tagNode(atPath: path) else { return }
        guard let normalizedName = TagPathNode.normalizedName(name) else {
            tagErrorMessage = String(localized: "Separate tag levels with a single slash, with a name on both sides.")
            return
        }

        let prefix = path + "/"
        let affected = tags.filter {
            let folded = TagPathNode.foldedKey($0.name)
            return folded == path || folded.hasPrefix(prefix)
        }
        guard !affected.isEmpty else { return }

        let oldDepth = node.displayPath.split(separator: "/", omittingEmptySubsequences: false).count
        let newPrefix = normalizedName.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let replacements: [(original: ArchiveTag, name: String)] = affected.map { tag in
            let components = tag.name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            return (tag, (newPrefix + components.dropFirst(oldDepth)).joined(separator: "/"))
        }

        let affectedIDs = Set(affected.map(\.id))
        let destinationKeys = replacements.map { TagPathNode.foldedKey($0.name) }
        let unaffectedKeys = Set(
            tags.lazy
                .filter { !affectedIDs.contains($0.id) }
                .map { TagPathNode.foldedKey($0.name) }
        )
        guard Set(destinationKeys).count == destinationKeys.count,
              destinationKeys.allSatisfy({ !unaffectedKeys.contains($0) }) else {
            tagErrorMessage = String(localized: "That tag path would conflict with an existing tag.")
            return
        }
        guard replacements.contains(where: { $0.original.name != $0.name }) else { return }

        tagErrorMessage = nil
        do {
            for replacement in replacements {
                var updatedTag = replacement.original
                updatedTag.name = replacement.name
                updatedTag.updatedAt = .now
                try await repository.save(tag: updatedTag)
                replace(updatedTag)
            }
        } catch {
            tagErrorMessage = error.localizedDescription
        }
    }

    /// Removes the tag, and takes it off every file carrying it.
    ///
    /// The files are written first: a tag id left on a file whose tag no longer exists would
    /// filter to nothing and show nowhere, which is a worse state than either end of this.
    func deleteTag(id: UUID) async {
        guard requireOnline(), let tag = tag(id: id) else { return }
        tagErrorMessage = nil
        do {
            for file in files where file.tagIDs.contains(tag.id) {
                var updatedFile = file
                updatedFile.tagIDs.removeAll { $0 == tag.id }
                updatedFile.updatedAt = .now
                try await repository.save(file: updatedFile)
                replace(updatedFile)
            }
            try await repository.delete(tag: tag)
            tags.removeAll { $0.id == tag.id }
        } catch {
            tagErrorMessage = error.localizedDescription
        }
    }

    /// Puts a tag on the given files, or takes it off all of them.
    ///
    /// One decision for the whole selection rather than one per file: a menu item that means
    /// something different for each row chosen cannot be labelled.
    func setTag(_ tagID: UUID, on fileIDs: [UUID], isOn: Bool) async {
        guard requireOnline(), let tag = tag(id: tagID) else { return }
        tagErrorMessage = nil
        let originals = fileIDs
            .compactMap(file(id:))
            .filter { $0.tagIDs.contains(tag.id) != isOn }
        guard !originals.isEmpty else { return }

        let updated = originals.map { original -> ArchiveFile in
            var file = original
            if isOn {
                file.tagIDs.append(tag.id)
            } else {
                file.tagIDs.removeAll { $0 == tag.id }
            }
            file.updatedAt = .now
            return file
        }
        apply(updated)

        do {
            let failures = try await repository.save(files: updated)
            if !failures.isEmpty {
                apply(originals.filter { failures[$0.id] != nil })
                tagErrorMessage = bulkFailureMessage(
                    failures,
                    of: updated.count,
                    verb: String(localized: "tag")
                )
            }
        } catch {
            apply(originals)
            tagErrorMessage = error.localizedDescription
            return
        }
        guard !isOn else { return }
        await pruneEmptyTags(among: [tagID])
    }

    /// Takes away a tag this device has just emptied.
    ///
    /// A tag is an attribute, not a container: it exists because something has it. There is no way
    /// to make an empty one — a new name is typed while putting it on a file — so a name nothing
    /// carries is not an empty shelf waiting to be filled, it is a leftover.
    ///
    /// Files in the Trash still count. They are being considered rather than gone, and a tag
    /// removed while its only file sits in the Trash would leave that file naming nothing when it
    /// came back.
    ///
    /// Only the tags an operation just touched, and only from the device that performed it. This
    /// used to run after every read as well, over every tag, and that deleted a reader's tags from
    /// under them: while one device imported bookmarks, another that merely came back on screen
    /// read an archive whose tag records had arrived and whose file records had not — CloudKit
    /// answers queries from an index that trails its own writes — and swept away every name it
    /// could not yet see a file for. Absence in a read is not evidence of absence, and it is never
    /// grounds to delete. A leftover name from an older version is a leftover name; it is not worth
    /// one destroyed tag.
    ///
    /// What remains is narrow and deliberate: another device may put this tag on a file in the
    /// moment between the write here and the check. The archive cannot be asked the question
    /// directly — `tagIDs` carries no queryable index, and a fresh read would trail the same way —
    /// so the answer comes from what this device knows, immediately after it was the one to change
    /// it.
    private func pruneEmptyTags(among tagIDs: Set<UUID>) async {
        guard !tagIDs.isEmpty else { return }
        let carried = Set((files + trashedFiles).flatMap(\.tagIDs))
        let orphans = tags.filter { tagIDs.contains($0.id) && !carried.contains($0.id) }
        guard !orphans.isEmpty else { return }
        for tag in orphans {
            do {
                try await repository.delete(tag: tag)
                tags.removeAll { $0.id == tag.id }
            } catch {
                tagErrorMessage = error.localizedDescription
                return
            }
        }
    }

    func beginCreatingTag(assigningTo fileIDs: [UUID] = []) {
        guard requireOnline() else { return }
        newTagName = ""
        tagErrorMessage = nil
        filesAwaitingNewTag = fileIDs
        isShowingNewTag = true
    }

    func createTagFromSheet() async {
        isCreatingTag = true
        defer { isCreatingTag = false }
        guard let tag = await createTag(named: newTagName) else { return }
        let waiting = filesAwaitingNewTag
        filesAwaitingNewTag = []
        isShowingNewTag = false
        if !waiting.isEmpty {
            await setTag(tag.id, on: waiting, isOn: true)
        }
    }

    func clearTagError() { tagErrorMessage = nil }

    private func sortedFiles(parentFolderID: UUID?) -> [ArchiveFile] {
        sorted(index.files(inFolderWithID: parentFolderID), by: sortMode)
    }

    private func sorted(_ siblings: [ArchiveFile], by sortMode: ArchiveSortMode) -> [ArchiveFile] {
        let ascending = ascending(siblings, by: sortMode)
        return sortAscending ? ascending : ascending.reversed()
    }

    /// Turned around whole when the order is reversed, ties and all, so that reversing twice puts
    /// every row back where it was.
    private func ascending(_ siblings: [ArchiveFile], by sortMode: ArchiveSortMode) -> [ArchiveFile] {
        switch sortMode {
        case .displayName:
            return siblings.sorted { nameOrder($0.sidebarDisplayName, $1.sidebarDisplayName) }
        case .importedAt:
            return siblings.sorted { ($0.importedAt, $0.sidebarDisplayName) < ($1.importedAt, $1.sidebarDisplayName) }
        case .format:
            return siblings.sorted { ($0.effectiveDisplayFormat.rawValue, $0.sidebarDisplayName) < ($1.effectiveDisplayFormat.rawValue, $1.sidebarDisplayName) }
        case .fileSize:
            return siblings.sorted { ($0.fileSize, $0.sidebarDisplayName) < ($1.fileSize, $1.sidebarDisplayName) }
        }
    }

    /// Folders stay ahead of files in every folder view, but Name and Date still describe both
    /// kinds of direct child. Format and Size are file attributes, so folders retain their stable
    /// name order for those modes. CloudKit does not promise query order, so every branch applies
    /// its own deterministic order.
    private func sortedFolders(parentFolderID: UUID?) -> [ArchiveFolder] {
        let siblings = index.folders(inFolderWithID: parentFolderID)
        switch sortMode {
        case .displayName:
            let ascending = siblings.sorted { nameOrder($0.name, $1.name) }
            return sortAscending ? ascending : ascending.reversed()
        case .importedAt:
            let ascending = siblings.sorted {
                if $0.createdAt == $1.createdAt {
                    return nameOrder($0.name, $1.name)
                }
                return $0.createdAt < $1.createdAt
            }
            return sortAscending ? ascending : ascending.reversed()
        case .format, .fileSize:
            return siblings.sorted { nameOrder($0.name, $1.name) }
        }
    }

    private func nameOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private var currentSnapshot: ArchiveSnapshot {
        ArchiveSnapshot(folders: folders, files: files, tags: tags)
    }


    /// Folders and files land where the user chose, with no operation-level folder wrapped around
    /// them. A folder import already carries its own root name in each relative path, so the
    /// hierarchy the user picked is what appears.
    private func makeImportFolderPlan(
        candidates: [ImportCandidate],
        requestedFolderPaths: [[String]] = []
    ) throws -> ImportFolderPlan {
        var plannedFolders: [ArchiveFolder] = []
        var destinationFolderIDs: [String: UUID?] = ["": importDestinationFolderID]

        let candidateFolderPaths = try candidates.map { candidate in
            guard case .viewable = candidate.detection else { throw ArchiveImportError.notViewable }
            guard !candidate.importPathComponents.isEmpty else {
                throw ImportBatchValidationError.invalidRelativePath
            }
            return Array(candidate.importPathComponents.dropLast())
        }
        let allFolderPaths = (requestedFolderPaths + candidateFolderPaths).sorted { $0.count < $1.count }
        for folderComponents in allFolderPaths {
            for componentCount in folderComponents.indices.map({ $0 + 1 }) {
                let components = Array(folderComponents.prefix(componentCount))
                let path = normalizedFolderPath(components)
                if destinationFolderIDs[path] != nil { continue }
                let parentPath = normalizedFolderPath(Array(components.dropLast()))
                guard let parentID = destinationFolderIDs[parentPath] else {
                    throw ImportBatchValidationError.invalidRelativePath
                }
                let folder = ArchiveFolder(
                    name: components.last ?? "",
                    parentFolderID: parentID
                )
                try ArchiveTreeValidator.validate(
                    folder: folder,
                    in: ArchiveSnapshot(folders: folders + plannedFolders, files: files)
                )
                plannedFolders.append(folder)
                destinationFolderIDs[path] = folder.id
            }
        }

        var plannedFiles = files
        for candidate in candidates {
            let pathComponents = candidate.importPathComponents
            let parentPath = normalizedFolderPath(Array(pathComponents.dropLast()))
            guard let parentID = destinationFolderIDs[parentPath],
                  let fileName = pathComponents.last,
                  case .viewable(let format, let encoding) = candidate.detection else {
                throw ImportBatchValidationError.invalidRelativePath
            }
            let file = ArchiveFile(
                originalFileName: fileName,
                parentFolderID: parentID,
                detectedFormat: format,
                sourceEncoding: encoding,
                fileSize: candidate.fileSize,
                contentHash: candidate.contentHash
            )
            try ArchiveTreeValidator.validate(
                file: file,
                in: ArchiveSnapshot(folders: folders + plannedFolders, files: plannedFiles)
            )
            plannedFiles.append(file)
        }
        return ImportFolderPlan(
            folders: plannedFolders,
            destinationFolderIDs: destinationFolderIDs
        )
    }

    private func normalizedFolderPath(_ components: [String]) -> String {
        components.map(ArchiveRules.normalizedName).joined(separator: "/")
    }

    private func removeTemporaryImportDirectories() {
        importPreflightResult?.temporaryDirectoryURLs.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }

    private func stopAccessingImportURLs() {
        securityScopedImportURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedImportURLs = []
    }


    private func replace(_ folder: ArchiveFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index] = folder
    }

    private func replace(_ tag: ArchiveTag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = tag
    }

    private func replace(_ file: ArchiveFile) {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[index] = file
    }

    private func isDescendant(_ candidateID: UUID, of ancestorID: UUID) -> Bool {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var currentID: UUID? = candidateID
        var visited = Set<UUID>()
        while let id = currentID, visited.insert(id).inserted {
            if id == ancestorID { return true }
            currentID = foldersByID[id]?.parentFolderID
        }
        return false
    }

    private func recoveredItemsFolder() async throws -> ArchiveFolder {
        let choice = ArchiveRestoration.recoveryFolder(in: currentSnapshot)
        guard choice.needsCreation else { return choice.folder }
        try ArchiveTreeValidator.validate(folder: choice.folder, in: currentSnapshot)
        try await repository.save(folder: choice.folder)
        folders.append(choice.folder)
        return choice.folder
    }

    private func restoredParentID(_ originalID: UUID?) async throws -> UUID? {
        switch ArchiveRestoration.destination(originalParentID: originalID, in: currentSnapshot) {
        case .root: return nil
        case .folder(let id): return id
        case .recovery: return try await recoveredItemsFolder().id
        }
    }

    private func availableRestoredName(for file: ArchiveFile, in parentID: UUID?) -> String? {
        ArchiveRestoration.availableFileName(for: file, in: parentID, visible: currentSnapshot)
    }

    private func requireOnline() -> Bool {
        guard !isOfflineMode, connectivity.isOnline() else {
            isOfflineMode = true
            offlineOperationMessage = "This change requires an internet connection. ArchiveLeaf does not queue offline changes."
            return false
        }
        return true
    }
}

private enum ImportBatchValidationError: LocalizedError {
    case invalidRelativePath

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            "The import contains an invalid relative path. Nothing was imported."
        }
    }
}

private enum OfflineArchiveError: LocalizedError {
    case contentNotDownloaded

    var errorDescription: String? {
        "This file has not been downloaded. Connect to the internet to view it."
    }
}

private struct ImportFolderPlan {
    let folders: [ArchiveFolder]
    let destinationFolderIDs: [String: UUID?]
}

private extension ArchiveItem {
    var parentFolderID: UUID? {
        switch self {
        case .folder(let folder): folder.parentFolderID
        case .file(let file): file.parentFolderID
        }
    }
}
