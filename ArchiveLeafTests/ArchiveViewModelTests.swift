import Foundation
import XCTest
@testable import ArchiveLeaf

@MainActor
final class ArchiveViewModelTests: XCTestCase {
    /// Choosing a file is an act, and a bookmark's page follows from the act rather than from which
    /// file is focused. The two are indistinguishable by state alone: the file restored at launch
    /// is focused exactly as the file just pressed is.
    func testAFileChoiceIsTakenOnceAndOnlyByTheFileItWasMadeFor() {
        let viewModel = ArchiveViewModel(repository: InMemoryArchiveRepository())
        let chosen = UUID()
        let other = UUID()

        XCTAssertFalse(viewModel.takeChoice(of: chosen), "A choice nobody made was taken")

        viewModel.noteFileChosen(chosen)

        XCTAssertFalse(viewModel.takeChoice(of: other), "Another file took this file's choice")
        XCTAssertTrue(viewModel.takeChoice(of: chosen))
        XCTAssertFalse(viewModel.takeChoice(of: chosen), "The same choice was taken twice")

        // Pressing the file already chosen is how a reader asks for its page again.
        viewModel.noteFileChosen(chosen)
        XCTAssertTrue(viewModel.takeChoice(of: chosen))
    }

    /// A launch asks the archive one question.
    ///
    /// The shelf and the Trash are the same records, so asking for them separately fetched every
    /// folder and every file three times over — and the two extra rounds could only arrive at what
    /// the first already held. Counted rather than timed: against the in-memory archive the reads
    /// are free, so nothing about the app's behaviour shows the difference, and a `loadTrash()`
    /// quietly put back into `load()` would look entirely correct.
    func testLoadingReadsTheArchiveOnceForBothTheShelfAndTheTrash() async {
        let folder = ArchiveFolder(name: "Prompts")
        let discarded = ArchiveFile(
            originalFileName: "old.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText
        )
        let repository = CountingArchiveRepository(
            folders: [folder],
            files: [ArchiveFile(originalFileName: "kept.txt", detectedFormat: .plainText), discarded]
        )
        let viewModel = ArchiveViewModel(repository: repository)

        await viewModel.load()

        let contentsReads = await repository.contentsReads
        let separateReads = await repository.separateReads
        XCTAssertEqual(contentsReads, 1)
        XCTAssertEqual(separateReads, 0, "The load path asked for the same records more than once")
        // And the Trash arrived with it, rather than waiting for its first visit.
        XCTAssertEqual(viewModel.trashedFiles.map(\.id), [discarded.id])
    }

    /// An import writes once and does not read the archive back.
    ///
    /// Counted rather than timed, for the same reason as the load above: in memory the reads are
    /// free, so a re-read put back here would look entirely correct while costing three queries over
    /// the whole archive on the real service — to find out something the import already knew.
    func testImportingWritesOnceAndDoesNotReadTheArchiveAgain() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("one".utf8).write(to: source.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: source.appendingPathComponent("two.txt"))

        let repository = CountingArchiveRepository()
        let viewModel = ArchiveViewModel(repository: repository)

        await viewModel.inspectImports(at: [source], into: nil)

        let fileWriteBatches = await repository.fileWriteBatches
        let folderWriteBatches = await repository.folderWriteBatches
        let contentsReads = await repository.contentsReads
        let separateReads = await repository.separateReads
        XCTAssertEqual(fileWriteBatches, [2])
        XCTAssertEqual(folderWriteBatches, [1])
        XCTAssertEqual(contentsReads, 0, "The import read the archive back")
        XCTAssertEqual(separateReads, 0, "The import read the archive back")
        XCTAssertEqual(viewModel.files.count, 2)
        XCTAssertEqual(viewModel.folders.map(\.name), ["Source"])
    }

    func testReloadAfterArchiveResetClearsSelectionAndPublishesEmptyState() async {
        let file = ArchiveFile(originalFileName: "note.txt", detectedFormat: .plainText)
        let repository = InMemoryArchiveRepository(files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)
        _ = await repository.resetArchive()

        await viewModel.adoptReplacedArchive(ArchiveSnapshot(folders: [], files: []))

        XCTAssertNil(viewModel.selection)
        XCTAssertEqual(viewModel.loadState, .empty)
        XCTAssertTrue(viewModel.files.isEmpty)
    }

    func testAdoptingARestoredArchiveShowsItWithoutRereadingTheRepository() async {
        let folder = ArchiveFolder(name: "Prompts")
        let file = ArchiveFile(
            originalFileName: "note.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        // Empty on read: CloudKit's query index trails its own writes, so a re-read right after a
        // restore can still answer with the archive as it was.
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: []))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        XCTAssertEqual(viewModel.loadState, .empty)

        await viewModel.adoptReplacedArchive(
            ArchiveSnapshot(folders: [folder], files: [file])
        )

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.folders.map(\.id), [folder.id])
        XCTAssertEqual(viewModel.files.map(\.id), [file.id])
        XCTAssertNil(viewModel.selection)
    }

    /// Launching read the whole archive; coming straight back must not read it again.
    func testReturningJustAfterLaunchDoesNotReadTheArchiveAgain() async {
        let repository = CountingSnapshotRepository()
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        await viewModel.load()
        await viewModel.refreshIfStale()

        let reads = await repository.snapshotReadCount
        XCTAssertEqual(reads, 1)
    }

    func testLoadPublishesEmptyState() async {
        let viewModel = ArchiveViewModel(repository: StubArchiveRepository(result: .success(ArchiveSnapshot(folders: [], files: []))))

        await viewModel.load()

        XCTAssertEqual(viewModel.loadState, .empty)
    }

    func testLoadPublishesLoadedState() async {
        let folder = ArchiveFolder(name: "Documents")
        let snapshot = ArchiveSnapshot(folders: [folder], files: [])
        let viewModel = ArchiveViewModel(repository: StubArchiveRepository(result: .success(snapshot)))

        await viewModel.load()

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.folders.map(\.id), [folder.id])
    }

    func testLoadPublishesICloudUnavailableState() async {
        let viewModel = ArchiveViewModel(repository: StubArchiveRepository(result: .failure(CloudKitRepositoryError.iCloudUnavailable)))

        await viewModel.load()

        XCTAssertEqual(viewModel.loadState, .iCloudUnavailable)
    }

    func testLoadPublishesFailureAndRetryCanRecover() async {
        let repository = StubArchiveRepository(result: .failure(TestError.failed))
        let viewModel = ArchiveViewModel(repository: repository)

        await viewModel.load()
        guard case .failed = viewModel.loadState else {
            return XCTFail("Expected failed state")
        }

        await repository.setResult(.success(ArchiveSnapshot(folders: [], files: [])))
        await viewModel.load()
        XCTAssertEqual(viewModel.loadState, .empty)
    }

    func testOfflineLoadUsesLastDownloadedSnapshotAndRejectsChanges() async throws {
        let folder = ArchiveFolder(name: "Downloaded")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let snapshotCache = DiskArchiveSnapshotCache(fileURL: fileURL)
        try await snapshotCache.storeSnapshot(ArchiveSnapshot(folders: [folder], files: []))
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .failure(TestError.failed)),
            snapshotCache: snapshotCache,
            connectivity: OfflineConnectivity()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertTrue(viewModel.isOfflineMode)
        XCTAssertEqual(viewModel.folders, [folder])

        viewModel.beginCreatingFolder(in: nil)
        XCTAssertFalse(viewModel.isShowingNewFolder)
        XCTAssertNotNil(viewModel.offlineOperationMessage)
    }

    func testSeparatesAndSortsRootAndFolderFiles() async {
        let folder = ArchiveFolder(name: "Documents")
        let rootB = ArchiveFile(
            originalFileName: "B.txt",
            detectedFormat: .plainText
        )
        let rootA = ArchiveFile(
            originalFileName: "A.txt",
            detectedFormat: .plainText
        )
        let child = ArchiveFile(
            originalFileName: "Child.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        let snapshot = ArchiveSnapshot(folders: [folder], files: [rootB, child, rootA])
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .success(snapshot)),
            defaults: scratchDefaults()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rootFiles.map(\.id), [rootA.id, rootB.id])
        XCTAssertEqual(viewModel.files(in: folder).map(\.id), [child.id])
    }

    /// The destination is whatever the caller names — the folder on screen. It used to be read from
    /// `selection`, which navigation never sets and folder edits change behind the user's back.
    func testImportsIntoTheFolderItWasGiven() async {
        let folder = ArchiveFolder(name: "Documents")
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("selected.txt")
        let candidate = ImportCandidate(
            sourceURL: sourceURL,
            detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
            fileSize: 1,
            sourceModifiedAt: nil,
            contentHash: "hash"
        )
        let importer = RecordingArchiveImporter()
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [folder], files: []))
        )
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: StaticImportPreflight(candidate: candidate),
            archiveImporter: importer
        )
        await viewModel.load()
        // Deliberately pointed elsewhere: it must not influence where the files land.
        viewModel.selection = nil

        await viewModel.inspectImports(at: [sourceURL], into: folder.id)
        await viewModel.importCandidates([candidate])
        let recordedDestination = await importer.destinationFolderID
        let savedFolders = await repository.savedFolders

        XCTAssertEqual(viewModel.importDestinationFolderID, folder.id)
        // A single file lands in the chosen folder itself; no folder is created to hold it.
        XCTAssertTrue(savedFolders.isEmpty)
        XCTAssertEqual(recordedDestination, folder.id)
    }

    func testFoldersUseNameOrderAndNewFolderUsesDefaultCompatibilityIndex() async {
        let parent = ArchiveFolder(name: "Parent")
        let sibling = ArchiveFolder(
            name: "Zulu",
            parentFolderID: parent.id,
            folderSortIndex: -100
        )
        let first = ArchiveFolder(name: "Alpha", parentFolderID: parent.id, folderSortIndex: 99)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [parent, sibling, first], files: []))
        )
        let viewModel = ArchiveViewModel(repository: repository, defaults: scratchDefaults())
        await viewModel.load()
        viewModel.beginCreatingFolder(in: parent.id)
        viewModel.newFolderName = "  Child  "

        await viewModel.createFolder()
        let savedFolder = await repository.savedFolders.last

        XCTAssertEqual(savedFolder?.name, "Child")
        XCTAssertEqual(savedFolder?.parentFolderID, parent.id)
        XCTAssertEqual(savedFolder?.folderSortIndex, 0)
        XCTAssertEqual(viewModel.folders(in: parent.id).map(\.name), ["Alpha", "Child", "Zulu"])
        XCTAssertEqual(viewModel.selection?.id, savedFolder?.id)
        XCTAssertFalse(viewModel.isShowingNewFolder)
    }

    func testFoldersFollowNameSortDirection() async {
        let parent = ArchiveFolder(name: "Parent")
        let zulu = ArchiveFolder(name: "Zulu", parentFolderID: parent.id)
        let alpha = ArchiveFolder(name: "Alpha", parentFolderID: parent.id)
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [parent, zulu, alpha], files: []))
            ),
            defaults: scratchDefaults()
        )
        await viewModel.load()
        viewModel.sortMode = .displayName

        viewModel.sortAscending = true
        XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [alpha.id, zulu.id])

        viewModel.sortAscending = false
        XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [zulu.id, alpha.id])
    }

    func testFoldersFollowCreatedDateSortDirection() async {
        let parent = ArchiveFolder(name: "Parent")
        let earlier = ArchiveFolder(
            name: "Zulu",
            parentFolderID: parent.id,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let sameDate = ArchiveFolder(
            name: "Alpha",
            parentFolderID: parent.id,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let later = ArchiveFolder(
            name: "Alpha",
            parentFolderID: parent.id,
            createdAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [parent, later, earlier, sameDate], files: []))
            ),
            defaults: scratchDefaults()
        )
        await viewModel.load()
        viewModel.sortMode = .importedAt

        viewModel.sortAscending = true
        XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [sameDate.id, earlier.id, later.id])

        viewModel.sortAscending = false
        XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [later.id, earlier.id, sameDate.id])
    }

    func testFoldersKeepAscendingNameOrderForFormatAndSize() async {
        let parent = ArchiveFolder(name: "Parent")
        let zulu = ArchiveFolder(name: "Zulu", parentFolderID: parent.id)
        let alpha = ArchiveFolder(name: "Alpha", parentFolderID: parent.id)
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [parent, zulu, alpha], files: []))
            ),
            defaults: scratchDefaults()
        )
        await viewModel.load()

        for mode in [ArchiveSortMode.format, .fileSize] {
            viewModel.sortMode = mode
            viewModel.sortAscending = true
            XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [alpha.id, zulu.id])

            viewModel.sortAscending = false
            XCTAssertEqual(viewModel.folders(in: parent.id).map(\.id), [alpha.id, zulu.id])
        }
    }

    func testFilesKeepUsingImportedDateSortDirection() async {
        let parent = ArchiveFolder(name: "Parent")
        let earlier = ArchiveFile(
            originalFileName: "Zulu.txt",
            parentFolderID: parent.id,
            detectedFormat: .plainText,
            importedAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let later = ArchiveFile(
            originalFileName: "Alpha.txt",
            parentFolderID: parent.id,
            detectedFormat: .plainText,
            importedAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [parent], files: [later, earlier]))
            ),
            defaults: scratchDefaults()
        )
        await viewModel.load()
        viewModel.sortMode = .importedAt

        viewModel.sortAscending = true
        XCTAssertEqual(viewModel.files(in: parent).map(\.id), [earlier.id, later.id])

        viewModel.sortAscending = false
        XCTAssertEqual(viewModel.files(in: parent).map(\.id), [later.id, earlier.id])
    }

    func testFolderCreationRejectsDuplicateBeforeRepositoryWrite() async {
        let existing = ArchiveFolder(name: "Documents")
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [existing], files: []))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.beginCreatingFolder(in: nil)
        viewModel.newFolderName = " documents "

        await viewModel.createFolder()
        let savedFolders = await repository.savedFolders

        XCTAssertTrue(savedFolders.isEmpty)
        XCTAssertEqual(
            viewModel.folderCreationErrorMessage,
            ArchiveValidationError.duplicateName.localizedDescription
        )
        XCTAssertTrue(viewModel.isShowingNewFolder)
    }

    func testExternalWebDropCreatesBookmarkInTheChosenFolder() async throws {
        let folder = ArchiveFolder(name: "Reading")
        let repository = InMemoryArchiveRepository(folders: [folder])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.inspectExternalDrop(
            at: [try XCTUnwrap(URL(string: "https://example.com/article"))],
            into: folder.id
        )

        let file = try XCTUnwrap(viewModel.files(in: folder.id).first)
        XCTAssertEqual(file.originalFileName, "example.com.webloc")
        XCTAssertEqual(file.sidebarDisplayName, "example.com")
        XCTAssertEqual(file.detectedFormat, .bookmark)
        let content = try await viewModel.loadContent(for: file)
        XCTAssertEqual(
            content,
            .bookmark(try XCTUnwrap(URL(string: "https://example.com/article")))
        )
    }

    func testExternalWeblocDropDisambiguatesAnotherPageFromTheSameHost() async throws {
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let firstData = try BookmarkDocument.data(for: firstURL)
        let first = ArchiveFile(
            originalFileName: "example.com.webloc",
            detectedFormat: .bookmark,
            fileSize: Int64(firstData.count),
            contentHash: "first-page-hash"
        )
        let repository = InMemoryArchiveRepository(
            files: [first],
            assetDataByFileID: [first.id: firstData]
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let droppedWebloc = try BookmarkDocument.write(
            url: try XCTUnwrap(URL(string: "https://example.com/second")),
            into: workspace
        )

        await viewModel.inspectExternalDrop(at: [droppedWebloc], into: nil)

        XCTAssertEqual(
            Set(viewModel.files.map(\.sidebarDisplayName)),
            ["example.com", "example.com 2"]
        )
        XCTAssertNil(viewModel.importErrorMessage)
    }

    func testExternalDropRejectsNonWebRemoteURLWithoutWriting() async throws {
        let repository = InMemoryArchiveRepository()
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.inspectExternalDrop(
            at: [try XCTUnwrap(URL(string: "mailto:someone@example.com"))],
            into: nil
        )

        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertEqual(
            viewModel.importErrorMessage,
            BookmarkDocumentError.invalidWebURL.localizedDescription
        )
    }

    func testRenamesFileDisplayNameWithoutChangingOriginalName() async {
        let file = ArchiveFile(originalFileName: "report.md", detectedFormat: .markdown)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: [file]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.beginRenaming(.file(file))
        viewModel.renameDraft = "  Notes  "

        await viewModel.renameItem()
        let savedFile = await repository.savedFiles.last

        XCTAssertEqual(savedFile?.originalFileName, "report.md")
        XCTAssertEqual(savedFile?.userDefinedName, "Notes")
        XCTAssertEqual(savedFile?.sidebarDisplayName, "Notes.md")
        XCTAssertNil(viewModel.itemBeingRenamed)
    }

    /// Dropping onto the folder pane names its destination outright, unlike a drop on another
    /// row, which had to be read as a move or a reorder from where in the row it landed.
    func testDropOnAFolderMovesTheFileIntoIt() async {
        let destination = ArchiveFolder(name: "Destination")
        let moving = ArchiveFile(originalFileName: "moving.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [destination], files: [moving]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.move(itemWithID: moving.id, into: destination.id)

        let savedFile = await repository.savedFiles.last
        XCTAssertEqual(savedFile?.id, moving.id)
        XCTAssertEqual(savedFile?.parentFolderID, destination.id)
        XCTAssertNil(viewModel.moveErrorMessage)
    }

    /// The archive row is a destination too, which is how a file comes back out of a folder.
    func testDropOnTheArchiveMovesTheFileToTheRoot() async {
        let folder = ArchiveFolder(name: "Somewhere")
        let moving = ArchiveFile(
            originalFileName: "moving.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [folder], files: [moving]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.move(itemWithID: moving.id, into: nil)

        let savedFile = await repository.savedFiles.last
        XCTAssertNil(savedFile?.parentFolderID)
    }

    /// A folder cannot be dropped into itself: the archive would have no way back to it.
    func testDropOnItselfIsRefused() async {
        let folder = ArchiveFolder(name: "Itself")
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [folder], files: []))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.move(itemWithID: folder.id, into: folder.id)

        let savedFolders = await repository.savedFolders
        XCTAssertTrue(savedFolders.isEmpty)
    }

    func testMovingFolderPreservesCompatibilitySortIndex() async {
        let destination = ArchiveFolder(name: "Destination")
        let moving = ArchiveFolder(name: "Moving", folderSortIndex: -42)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [destination, moving], files: []))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.move(itemWithID: moving.id, into: destination.id)

        let savedFolder = await repository.savedFolders.last
        XCTAssertEqual(savedFolder?.id, moving.id)
        XCTAssertEqual(savedFolder?.parentFolderID, destination.id)
        XCTAssertEqual(savedFolder?.folderSortIndex, -42)
    }

    func testMovesFileToFolderAtEndOfDestination() async {
        let destination = ArchiveFolder(name: "Destination")
        let existing = ArchiveFile(
            originalFileName: "existing.txt",
            parentFolderID: destination.id,
            detectedFormat: .plainText
        )
        let moving = ArchiveFile(originalFileName: "moving.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(
                folders: [destination],
                files: [existing, moving]
            ))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.beginMoving([.file(moving)])
        viewModel.moveDestinationFolderID = destination.id

        await viewModel.moveItem()
        let savedFile = await repository.savedFiles.last

        XCTAssertEqual(savedFile?.parentFolderID, destination.id)
        XCTAssertTrue(viewModel.itemsBeingMoved.isEmpty)
    }

    func testFavoriteFilesAreFilteredAndSortedByDisplayName() async {
        let zulu = ArchiveFile(
            originalFileName: "zulu.txt",
            isFavorite: true,
            detectedFormat: .plainText
        )
        let alpha = ArchiveFile(
            originalFileName: "alpha.txt",
            isFavorite: true,
            detectedFormat: .plainText
        )
        let ordinary = ArchiveFile(
            originalFileName: "ordinary.txt",
            detectedFormat: .plainText
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [], files: [zulu, ordinary, alpha]))
            ),
            defaults: scratchDefaults()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.favoriteFiles.map(\.id), [alpha.id, zulu.id])
    }

    /// Somewhere of its own to keep a sorting choice, so the process's own settings are left alone.
    private func scratchDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "ArchiveLeafTests.\(UUID().uuidString)")!
        addTeardownBlock { suite.removePersistentDomain(forName: suite.description) }
        return suite
    }

    func testReversingTheOrderTurnsEveryListAround() async {
        let alpha = ArchiveFile(originalFileName: "alpha.txt", detectedFormat: .plainText)
        let mike = ArchiveFile(
            originalFileName: "mike.txt",
            isFavorite: true,
            detectedFormat: .plainText
        )
        let zulu = ArchiveFile(
            originalFileName: "zulu.txt",
            isFavorite: true,
            detectedFormat: .plainText
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [], files: [zulu, alpha, mike]))
            ),
            defaults: scratchDefaults()
        )
        await viewModel.load()
        viewModel.sortMode = .displayName
        viewModel.sortAscending = true

        XCTAssertEqual(viewModel.rootFiles.map(\.id), [alpha.id, mike.id, zulu.id])
        XCTAssertEqual(viewModel.favoriteFiles.map(\.id), [mike.id, zulu.id])

        viewModel.sortAscending = false

        XCTAssertEqual(viewModel.rootFiles.map(\.id), [zulu.id, mike.id, alpha.id])
        XCTAssertEqual(viewModel.favoriteFiles.map(\.id), [zulu.id, mike.id])
    }

    func testMovingSeveralItemsTakesThemAllToTheSameFolder() async {
        let destination = ArchiveFolder(name: "Destination")
        let first = ArchiveFile(originalFileName: "one.txt", detectedFormat: .plainText)
        let second = ArchiveFile(originalFileName: "two.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(result: .success(
            ArchiveSnapshot(folders: [destination], files: [first, second])
        ))
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        viewModel.beginMoving([.file(first), .file(second)])
        viewModel.moveDestinationFolderID = destination.id
        await viewModel.moveItem()

        XCTAssertEqual(
            Set(viewModel.files(in: destination).map(\.id)),
            [first.id, second.id]
        )
        XCTAssertTrue(viewModel.itemsBeingMoved.isEmpty)
    }

    func testTrashingSeveralItemsTakesThemAll() async {
        let first = ArchiveFile(originalFileName: "one.txt", detectedFormat: .plainText)
        let second = ArchiveFile(originalFileName: "two.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(result: .success(
            ArchiveSnapshot(folders: [], files: [first, second])
        ))
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        viewModel.itemsPendingTrash = [.file(first), .file(second)]
        await viewModel.moveToTrash(viewModel.itemsPendingTrash.map(\.id))

        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertEqual(Set(viewModel.trashedFiles.map(\.id)), [first.id, second.id])
    }

    func testToggleFavoritePersistsAndUpdatesSelection() async {
        let file = ArchiveFile(originalFileName: "note.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: [file]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)

        await viewModel.toggleFavorite(file.id)
        let savedFile = await repository.savedFiles.last

        XCTAssertEqual(savedFile?.isFavorite, true)
        XCTAssertEqual(viewModel.favoriteFiles.map(\.id), [file.id])
        guard case .file(let selectedFile) = viewModel.selection else {
            return XCTFail("Expected the selected file to remain selected")
        }
        XCTAssertTrue(selectedFile.isFavorite)
    }

    func testDisplayFormatOverridePersistsAndUpdatesSelection() async {
        let file = ArchiveFile(originalFileName: "note.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: [file]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)

        await viewModel.setDisplayFormat(.markdown, for: file)

        let savedFile = await repository.savedFiles.last
        XCTAssertEqual(savedFile?.displayFormatOverride, .markdown)
        guard case .file(let selectedFile) = viewModel.selection else {
            return XCTFail("Expected the selected file to remain selected")
        }
        XCTAssertEqual(selectedFile.effectiveDisplayFormat, .markdown)
    }

    func testSourceEncodingOverridePersistsWithoutChangingTheRecordedEncoding() async {
        let file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            sourceEncoding: "shift_jis"
        )
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: [file]))
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)

        await viewModel.setSourceEncoding(.windows31J, for: file)

        let savedFile = await repository.savedFiles.last
        XCTAssertEqual(savedFile?.sourceEncodingOverride, .windows31J)
        XCTAssertEqual(savedFile?.sourceEncoding, "shift_jis")
        guard case .file(let selectedFile) = viewModel.selection else {
            return XCTFail("Expected the selected file to remain selected")
        }
        XCTAssertEqual(selectedFile.effectiveTextEncoding, .windows31J)
    }

    func testInternalDropOntoFileDoesNothing() async {
        let first = ArchiveFile(originalFileName: "First.txt", detectedFormat: .plainText)
        let second = ArchiveFile(originalFileName: "Second.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(result: .success(
            ArchiveSnapshot(folders: [], files: [first, second])
        ))
        let viewModel = ArchiveViewModel(repository: repository, defaults: scratchDefaults())
        await viewModel.load()

        await viewModel.handleInternalDrop(
            draggedID: second.id,
            onto: .file(first),
            moveIntoFolder: false
        )
        let savedFiles = await repository.savedFiles

        XCTAssertTrue(savedFiles.isEmpty)
        XCTAssertEqual(viewModel.rootFiles.map(\.id), [first.id, second.id])
    }

    func testInternalDropOntoFolderMovesFile() async {
        let destination = ArchiveFolder(name: "Destination")
        let file = ArchiveFile(originalFileName: "Note.txt", detectedFormat: .plainText)
        let repository = StubArchiveRepository(result: .success(
            ArchiveSnapshot(folders: [destination], files: [file])
        ))
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()

        await viewModel.handleInternalDrop(
            draggedID: file.id,
            onto: .folder(destination),
            moveIntoFolder: true
        )
        let savedFile = await repository.savedFiles.last

        XCTAssertEqual(savedFile?.parentFolderID, destination.id)
        XCTAssertEqual(viewModel.files(in: destination).map(\.id), [file.id])
    }

    func testFolderMoveDestinationsExcludeSelfAndDescendants() async {
        let parent = ArchiveFolder(name: "Parent")
        let child = ArchiveFolder(name: "Child", parentFolderID: parent.id)
        let unrelated = ArchiveFolder(name: "Unrelated")
        let snapshot = ArchiveSnapshot(folders: [parent, child, unrelated], files: [])
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .success(snapshot))
        )
        await viewModel.load()

        viewModel.beginMoving([.folder(parent)])

        XCTAssertEqual(viewModel.availableMoveDestinationFolders.map(\.id), [unrelated.id])
    }

    func testFolderMoveDestinationsExcludeEverySelectedFolderAndItsDescendants() async {
        let first = ArchiveFolder(name: "First")
        let firstChild = ArchiveFolder(name: "First Child", parentFolderID: first.id)
        let firstGrandchild = ArchiveFolder(name: "First Grandchild", parentFolderID: firstChild.id)
        let second = ArchiveFolder(name: "Second")
        let secondChild = ArchiveFolder(name: "Second Child", parentFolderID: second.id)
        let secondGrandchild = ArchiveFolder(name: "Second Grandchild", parentFolderID: secondChild.id)
        let unrelated = ArchiveFolder(name: "Unrelated")
        let snapshot = ArchiveSnapshot(
            folders: [
                first,
                firstChild,
                firstGrandchild,
                second,
                secondChild,
                secondGrandchild,
                unrelated,
            ],
            files: []
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .success(snapshot))
        )
        await viewModel.load()

        viewModel.beginMoving([.folder(first), .folder(second)])

        XCTAssertEqual(viewModel.availableMoveDestinationFolders.map(\.id), [unrelated.id])
    }

    func testMixedMoveDestinationsIgnoreSelectedFilesWhenExcludingFolderSubtrees() async {
        let parent = ArchiveFolder(name: "Parent")
        let child = ArchiveFolder(name: "Child", parentFolderID: parent.id)
        let unrelated = ArchiveFolder(name: "Unrelated")
        let file = ArchiveFile(originalFileName: "Note.txt", detectedFormat: .plainText)
        let snapshot = ArchiveSnapshot(
            folders: [parent, child, unrelated],
            files: [file]
        )
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .success(snapshot))
        )
        await viewModel.load()

        viewModel.beginMoving([.file(file), .folder(parent)])

        XCTAssertEqual(viewModel.availableMoveDestinationFolders.map(\.id), [unrelated.id])
    }

    func testFileOnlyMoveDestinationsIncludeEveryFolder() async {
        let alpha = ArchiveFolder(name: "Alpha")
        let beta = ArchiveFolder(name: "Beta", parentFolderID: alpha.id)
        let first = ArchiveFile(originalFileName: "First.txt", detectedFormat: .plainText)
        let second = ArchiveFile(originalFileName: "Second.txt", detectedFormat: .plainText)
        let snapshot = ArchiveSnapshot(folders: [beta, alpha], files: [first, second])
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(result: .success(snapshot))
        )
        await viewModel.load()

        viewModel.beginMoving([.file(first), .file(second)])

        XCTAssertEqual(
            Set(viewModel.availableMoveDestinationFolders.map(\.id)),
            [alpha.id, beta.id]
        )
    }

    /// One file the archive refuses is one file the reader is told about. It used to end the run:
    /// everything selected after it was reported as never attempted.
    func testBatchImportKeepsWhatLandedAndNamesWhatDidNot() async {
        let candidates = ["one.txt", "fail.txt", "two.txt"].map { name in
            ImportCandidate(
                sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
                detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
                fileSize: 1,
                sourceModifiedAt: nil,
                contentHash: name
            )
        }
        let importer = PartialArchiveImporter(failingFileName: "fail.txt")
        let viewModel = ArchiveViewModel(
            repository: StubArchiveRepository(
                result: .success(ArchiveSnapshot(folders: [], files: []))
            ),
            archiveImporter: importer
        )

        await viewModel.importCandidates(candidates)

        XCTAssertEqual(
            viewModel.importResult?.importedFiles.map(\.originalFileName),
            ["one.txt", "two.txt"]
        )
        XCTAssertEqual(
            viewModel.importResult?.failures.map(\.sourceURL.lastPathComponent),
            ["fail.txt"]
        )
        XCTAssertEqual(viewModel.files.map(\.originalFileName), ["one.txt", "two.txt"])
        XCTAssertEqual(viewModel.importResult?.createdFolders.count, 0)
        XCTAssertEqual(viewModel.folders.count, 0)
    }

    func testPreflightFailurePreventsAllRepositoryWrites() async {
        let candidate = ImportCandidate(
            sourceURL: URL(fileURLWithPath: "/tmp/valid.txt"),
            detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
            fileSize: 1,
            sourceModifiedAt: nil,
            contentHash: "hash"
        )
        let failure = ImportFailure(
            sourceURL: URL(fileURLWithPath: "/tmp/invalid.bin"),
            reason: "Unsupported"
        )
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: []))
        )
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: StaticImportPreflight(candidate: candidate, failures: [failure]),
            archiveImporter: RecordingArchiveImporter()
        )

        await viewModel.inspectImports(at: [candidate.sourceURL], into: nil)
        let savedFolders = await repository.savedFolders
        let savedFiles = await repository.savedFiles

        XCTAssertTrue(savedFolders.isEmpty)
        XCTAssertTrue(savedFiles.isEmpty)
        // Nothing is asked before importing, so the refusal has to be reported afterwards.
        XCTAssertEqual(viewModel.importErrorMessage, "invalid.bin: Unsupported")
    }

    func testImportCreatesFoldersForCandidateRelativePath() async throws {
        let candidate = ImportCandidate(
            sourceURL: URL(fileURLWithPath: "/tmp/note.txt"),
            detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
            fileSize: 1,
            sourceModifiedAt: nil,
            contentHash: "hash",
            relativePathComponents: ["First", "Second", "note.txt"]
        )
        let repository = StubArchiveRepository(
            result: .success(ArchiveSnapshot(folders: [], files: []))
        )
        let importer = RecordingArchiveImporter()
        let viewModel = ArchiveViewModel(repository: repository, archiveImporter: importer)

        await viewModel.importCandidates([candidate])
        let createdFolders = try XCTUnwrap(viewModel.importResult?.createdFolders)
        let destinationID = await importer.destinationFolderID

        XCTAssertEqual(createdFolders.count, 2)
        XCTAssertEqual(createdFolders[0].name, "First")
        XCTAssertNil(createdFolders[0].parentFolderID)
        XCTAssertEqual(createdFolders[1].name, "Second")
        XCTAssertEqual(createdFolders[1].parentFolderID, createdFolders[0].id)
        XCTAssertEqual(destinationID, createdFolders[1].id)
    }
}

private enum TestError: Error {
    case failed
}

private struct OfflineConnectivity: ConnectivityChecking {
    func isOnline() -> Bool { false }
}

private actor CountingSnapshotRepository: ArchiveRepository {
    private(set) var snapshotReadCount = 0

    func fetchSnapshot() -> ArchiveSnapshot {
        snapshotReadCount += 1
        return ArchiveSnapshot(folders: [], files: [])
    }

    func fetchTrashedFiles() -> [ArchiveFile] { [] }
    func fetchTrashedFolders() -> [ArchiveFolder] { [] }
    func fileContentURL(for fileID: UUID) throws -> URL { throw ArchiveLeafError.notImplemented }
    func save(folder: ArchiveFolder) {}
    func save(tag: ArchiveTag) {}
    func delete(tag: ArchiveTag) {}
    func save(file: ArchiveFile) {}
    func save(file: ArchiveFile, assetURL: URL) {}
}

private actor StubArchiveRepository: ArchiveRepository {
    private var result: Result<ArchiveSnapshot, Error>
    private(set) var savedFolders: [ArchiveFolder] = []
    private(set) var savedFiles: [ArchiveFile] = []
    private(set) var savedTags: [ArchiveTag] = []

    init(result: Result<ArchiveSnapshot, Error>) {
        self.result = result
    }

    func setResult(_ result: Result<ArchiveSnapshot, Error>) {
        self.result = result
    }

    func fetchSnapshot() throws -> ArchiveSnapshot {
        try result.get()
    }

    func fetchTrashedFiles() -> [ArchiveFile] { [] }
    func fetchTrashedFolders() -> [ArchiveFolder] { [] }

    func fileContentURL(for fileID: UUID) throws -> URL {
        throw ArchiveLeafError.notImplemented
    }

    func save(folder: ArchiveFolder) throws {
        savedFolders.append(folder)
    }

    func save(tag: ArchiveTag) throws {
        savedTags.append(tag)
    }

    func delete(tag: ArchiveTag) throws {
        savedTags.removeAll { $0.id == tag.id }
    }

    func save(file: ArchiveFile) throws {
        savedFiles.append(file)
    }
    func save(file: ArchiveFile, assetURL: URL) throws {
        savedFiles.append(file)
    }
}

private struct StaticImportPreflight: ImportPreflightChecking {
    let candidate: ImportCandidate
    var failures: [ImportFailure] = []

    func inspect(urls: [URL]) -> ImportPreflightResult {
        ImportPreflightResult(candidates: [candidate], failures: failures)
    }
}

private actor RecordingArchiveImporter: ArchiveImporting {
    private(set) var destinationFolderID: UUID?
    private(set) var callCount = 0

    func importFiles(_ placements: [ImportPlacement]) -> ArchiveImportOutcome {
        callCount += 1
        destinationFolderID = placements.last?.folderID
        return ArchiveImportOutcome(
            importedFiles: placements.map(TestImportedFile.make),
            failures: []
        )
    }
}

private struct PartialArchiveImporter: ArchiveImporting {
    let failingFileName: String

    func importFiles(_ placements: [ImportPlacement]) -> ArchiveImportOutcome {
        var imported: [ArchiveFile] = []
        var failures: [ImportFailure] = []
        for placement in placements {
            if placement.candidate.sourceURL.lastPathComponent == failingFileName {
                failures.append(ImportFailure(
                    sourceURL: placement.candidate.sourceURL,
                    reason: "failed"
                ))
            } else {
                imported.append(TestImportedFile.make(placement))
            }
        }
        return ArchiveImportOutcome(importedFiles: imported, failures: failures)
    }
}

private enum TestImportedFile {
    static func make(_ placement: ImportPlacement) -> ArchiveFile {
        ArchiveFile(
            originalFileName: placement.candidate.sourceURL.lastPathComponent,
            parentFolderID: placement.folderID,
            detectedFormat: .plainText,
            fileSize: placement.candidate.fileSize,
            contentHash: placement.candidate.contentHash
        )
    }
}

/// Answers from an in-memory archive while recording what it was asked.
///
/// It answers `fetchContents` itself rather than letting the protocol's default fan out to the
/// four separate reads, because that fanning out is exactly what the counting is here to detect.
private actor CountingArchiveRepository: ArchiveRepository {
    private let backing: InMemoryArchiveRepository
    private(set) var contentsReads = 0
    private(set) var separateReads = 0

    init(folders: [ArchiveFolder] = [], files: [ArchiveFile] = [], tags: [ArchiveTag] = []) {
        backing = InMemoryArchiveRepository(folders: folders, files: files, tags: tags)
    }

    func fetchContents() async throws -> ArchiveContents {
        contentsReads += 1
        let snapshot = await backing.fetchSnapshot()
        return ArchiveContents(
            snapshot: snapshot,
            trashedFiles: await backing.fetchTrashedFiles(),
            trashedFolders: await backing.fetchTrashedFolders(),
            trashedFolderItemCounts: try await backing.fetchTrashedFolderItemCounts()
        )
    }

    func fetchSnapshot() async throws -> ArchiveSnapshot {
        separateReads += 1
        return await backing.fetchSnapshot()
    }

    func fetchTrashedFiles() async throws -> [ArchiveFile] {
        separateReads += 1
        return await backing.fetchTrashedFiles()
    }

    func fetchTrashedFolders() async throws -> [ArchiveFolder] {
        separateReads += 1
        return await backing.fetchTrashedFolders()
    }

    func fetchTrashedFolderItemCounts() async throws -> [UUID: Int] {
        separateReads += 1
        return try await backing.fetchTrashedFolderItemCounts()
    }

    func fileContentURL(for fileID: UUID) async throws -> URL {
        try await backing.fileContentURL(for: fileID)
    }
    func save(folder: ArchiveFolder) async throws { try await backing.save(folder: folder) }
    func save(file: ArchiveFile) async throws { try await backing.save(file: file) }
    func save(file: ArchiveFile, assetURL: URL) async throws {
        try await backing.save(file: file, assetURL: assetURL)
    }
    func save(tag: ArchiveTag) async throws { await backing.save(tag: tag) }
    func delete(tag: ArchiveTag) async throws { await backing.delete(tag: tag) }

    private(set) var fileWriteBatches: [Int] = []
    private(set) var folderWriteBatches: [Int] = []

    func create(files: [ArchiveFileAsset]) async throws -> [UUID: any Error] {
        fileWriteBatches.append(files.count)
        return try await backing.create(files: files)
    }

    func create(folders: [ArchiveFolder]) async throws {
        folderWriteBatches.append(folders.count)
        try await backing.create(folders: folders)
    }
}
