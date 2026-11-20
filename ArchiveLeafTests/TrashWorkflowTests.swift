import XCTest
@testable import ArchiveLeaf

@MainActor
final class TrashWorkflowTests: XCTestCase {
    func testMovingFileToTrashPreservesOriginalParent() async throws {
        let folder = ArchiveFolder(name: "Documents")
        let file = ArchiveFile(
            originalFileName: "note.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            contentHash: "hash"
        )
        let repository = InMemoryArchiveRepository(folders: [folder], files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)
        viewModel.itemsPendingTrash = [.file(file)]

        await viewModel.moveToTrash(viewModel.itemsPendingTrash.map(\.id))
        let trashedFiles = await repository.fetchTrashedFiles()
        let trashed = try XCTUnwrap(trashedFiles.first)

        XCTAssertTrue(trashed.isTrashed)
        XCTAssertEqual(trashed.originalParentFolderID, folder.id)
        XCTAssertNil(viewModel.selection)
        XCTAssertTrue(viewModel.files.isEmpty)
    }

    func testMoveToTrashAcceptsCapturedItemAfterDialogStateIsCleared() async throws {
        let file = ArchiveFile(originalFileName: "note.txt", detectedFormat: .plainText)
        let repository = InMemoryArchiveRepository(files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.itemsPendingTrash = [.file(file)]
        // As the dialog does on its way out, before the work has run.
        viewModel.itemsPendingTrash = []

        await viewModel.moveToTrash([file.id])

        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertEqual(viewModel.trashedFiles.map(\.id), [file.id])
    }

    func testRestoreReturnsFileToAvailableOriginalFolder() async throws {
        let folder = ArchiveFolder(name: "Documents")
        let file = ArchiveFile(
            originalFileName: "note.txt",
            originalParentFolderID: folder.id,
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText,
            contentHash: "hash"
        )
        let repository = InMemoryArchiveRepository(folders: [folder], files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadTrash()

        await viewModel.restore(file)
        let snapshot = await repository.fetchSnapshot()
        let restored = try XCTUnwrap(snapshot.files.first)

        XCTAssertEqual(restored.parentFolderID, folder.id)
        XCTAssertNil(restored.originalParentFolderID)
        XCTAssertFalse(restored.isTrashed)
    }

    func testRestoreUsesRecoveredItemsWhenOriginalFolderIsMissing() async throws {
        let file = ArchiveFile(
            originalFileName: "lost.txt",
            originalParentFolderID: UUID(),
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText,
            contentHash: "hash"
        )
        let repository = InMemoryArchiveRepository(files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadTrash()

        await viewModel.restore(file)
        let snapshot = await repository.fetchSnapshot()
        let recoveryFolder = try XCTUnwrap(snapshot.folders.first)
        let restored = try XCTUnwrap(snapshot.files.first)

        XCTAssertEqual(recoveryFolder.name, "Recovered Items")
        XCTAssertEqual(restored.parentFolderID, recoveryFolder.id)
        XCTAssertEqual(viewModel.selection?.id, restored.id)
    }

    func testFolderTrashAndRestorePreservesWholeSubtree() async throws {
        let root = ArchiveFolder(name: "Root")
        let child = ArchiveFolder(name: "Child", parentFolderID: root.id)
        let file = ArchiveFile(
            originalFileName: "nested.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText,
            contentHash: "hash"
        )
        let repository = InMemoryArchiveRepository(folders: [root, child], files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        viewModel.selection = .file(file)
        viewModel.itemsPendingTrash = [.folder(root)]

        await viewModel.moveToTrash(viewModel.itemsPendingTrash.map(\.id))
        let hiddenSnapshot = await repository.fetchSnapshot()
        let trashedFolders = await repository.fetchTrashedFolders()

        XCTAssertTrue(hiddenSnapshot.folders.isEmpty)
        XCTAssertTrue(hiddenSnapshot.files.isEmpty)
        XCTAssertEqual(trashedFolders.map(\.id), [root.id])
        XCTAssertNil(viewModel.selection)

        await viewModel.restore(try XCTUnwrap(trashedFolders.first))
        let restoredSnapshot = await repository.fetchSnapshot()

        XCTAssertEqual(Set(restoredSnapshot.folders.map(\.id)), Set([root.id, child.id]))
        XCTAssertEqual(restoredSnapshot.files.map(\.id), [file.id])
        XCTAssertEqual(viewModel.selection?.id, root.id)
    }

    func testFolderRestoreAfterReloadUsesRecoveredItemsWhenParentIsMissing() async throws {
        let missingParentID = UUID()
        let root = ArchiveFolder(
            name: "Lost Folder",
            originalParentFolderID: missingParentID,
            isTrashed: true,
            trashedAt: .now
        )
        let child = ArchiveFolder(name: "Child", parentFolderID: root.id)
        let file = ArchiveFile(
            originalFileName: "nested.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText,
            contentHash: "hash"
        )
        let repository = InMemoryArchiveRepository(folders: [root, child], files: [file])
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadTrash()

        await viewModel.restore(root)
        let snapshot = await repository.fetchSnapshot()
        let recoveredItems = try XCTUnwrap(snapshot.folders.first(where: { $0.name == "Recovered Items" }))
        let restoredRoot = try XCTUnwrap(snapshot.folders.first(where: { $0.id == root.id }))

        XCTAssertEqual(restoredRoot.parentFolderID, recoveredItems.id)
        XCTAssertTrue(snapshot.folders.contains(where: { $0.id == child.id }))
        XCTAssertTrue(snapshot.files.contains(where: { $0.id == file.id }))
    }

    func testPermanentDeleteKeepsTheRestListedWhenTrashQueriesLagBehind() async throws {
        let keep = ArchiveFile(originalFileName: "keep.txt", detectedFormat: .plainText)
        let remove = ArchiveFile(originalFileName: "remove.txt", detectedFormat: .plainText)
        let repository = LaggingTrashRepository(
            InMemoryArchiveRepository(
                files: [keep, remove],
                assetDataByFileID: [keep.id: Data("keep".utf8), remove.id: Data("remove".utf8)]
            )
        )
        let viewModel = ArchiveViewModel(repository: repository)
        await viewModel.load()
        await viewModel.moveToTrash(keep.id)
        await viewModel.moveToTrash(remove.id)
        XCTAssertEqual(viewModel.trashedFiles.count, 2)

        // From here the repository answers trash queries from a view that predates those writes,
        // the way CloudKit's index does immediately after one.
        await repository.startLagging()
        await viewModel.permanentlyDelete(.file(remove))

        XCTAssertEqual(viewModel.trashedFiles.map(\.id), [keep.id])
        XCTAssertNil(viewModel.trashErrorMessage)
    }
}

/// Forwards to a real repository, but can be told to answer trash queries as if the write index
/// has not caught up yet — returning nothing rather than what was just written.
private actor LaggingTrashRepository: ArchiveRepository, DuplicateFileLookingUp {
    private let base: InMemoryArchiveRepository
    private var isLagging = false

    init(_ base: InMemoryArchiveRepository) { self.base = base }

    func startLagging() { isLagging = true }

    func fetchSnapshot() async throws -> ArchiveSnapshot { await base.fetchSnapshot() }
    func fetchTrashedFiles() async throws -> [ArchiveFile] {
        isLagging ? [] : await base.fetchTrashedFiles()
    }
    func fetchTrashedFolders() async throws -> [ArchiveFolder] {
        isLagging ? [] : await base.fetchTrashedFolders()
    }
    func fileContentURL(for fileID: UUID) async throws -> URL {
        try await base.fileContentURL(for: fileID)
    }
    func save(folder: ArchiveFolder) async throws { try await base.save(folder: folder) }

    func save(tag: ArchiveTag) async throws { await base.save(tag: tag) }

    func delete(tag: ArchiveTag) async throws { await base.delete(tag: tag) }
    func save(file: ArchiveFile) async throws { try await base.save(file: file) }
    func save(file: ArchiveFile, assetURL: URL) async throws {
        try await base.save(file: file, assetURL: assetURL)
    }
    func permanentlyDelete(_ item: ArchiveItem) async throws -> ArchiveDeletionResult {
        try await base.permanentlyDelete(item)
    }
    func emptyTrash() async throws -> ArchiveDeletionResult { try await base.emptyTrash() }
    func files(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile] {
        await base.files(matchingContentHashes: hashes)
    }

    func testCountsWhatComesBackWithATrashedFolder() {
        let outer = ArchiveFolder(name: "Outer", isTrashed: true)
        let inner = ArchiveFolder(name: "Inner", parentFolderID: outer.id)
        let untouched = ArchiveFolder(name: "Elsewhere")
        let files = [
            ArchiveFile(
                originalFileName: "top.txt",
                parentFolderID: outer.id,
                detectedFormat: .plainText,
                importState: .completed
            ),
            ArchiveFile(
                originalFileName: "deep.txt",
                parentFolderID: inner.id,
                detectedFormat: .plainText,
                importState: .completed
            ),
            ArchiveFile(
                originalFileName: "already-trashed.txt",
                parentFolderID: inner.id,
                isTrashed: true,
                detectedFormat: .plainText,
                importState: .completed
            ),
            ArchiveFile(
                originalFileName: "outside.txt",
                parentFolderID: untouched.id,
                detectedFormat: .plainText,
                importState: .completed
            ),
        ]

        let counts = ArchiveTrashFilter.itemCountsUnderTrashedFolders(
            folders: [outer, inner, untouched],
            files: files
        )

        // The folder inside, and the two files that would come back with it.
        XCTAssertEqual(counts, [outer.id: 3])
    }
}
