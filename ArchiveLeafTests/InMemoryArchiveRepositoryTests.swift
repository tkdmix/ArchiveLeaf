import XCTest
@testable import ArchiveLeaf

final class InMemoryArchiveRepositoryTests: XCTestCase {
    func testSnapshotFoldersUseNameOrderInsteadOfCompatibilityIndex() async {
        let zulu = ArchiveFolder(name: "Zulu", folderSortIndex: -10)
        let alpha = ArchiveFolder(name: "Alpha", folderSortIndex: 20)
        let repository = InMemoryArchiveRepository(folders: [zulu, alpha])

        let snapshot = await repository.fetchSnapshot()

        XCTAssertEqual(snapshot.folders.map(\.name), ["Alpha", "Zulu"])
        XCTAssertEqual(snapshot.folders.map(\.folderSortIndex), [20, -10])
    }

    func testSnapshotOnlyPublishesCompletedNonTrashedItems() async throws {
        let folder = ArchiveFolder(name: "Folder")
        let completed = ArchiveFile(
            originalFileName: "completed.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        let pending = ArchiveFile(
            originalFileName: "pending.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            importState: .uploading
        )
        let trashed = ArchiveFile(
            originalFileName: "trashed.txt",
            parentFolderID: folder.id,
            isTrashed: true,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            folders: [folder],
            files: [completed, pending, trashed]
        )

        let snapshot = await repository.fetchSnapshot()

        XCTAssertEqual(snapshot.files.map(\.id), [completed.id])
    }

    func testSaveRejectsDuplicateNormalizedName() async throws {
        let existing = ArchiveFolder(name: "Résumé")
        let repository = InMemoryArchiveRepository(folders: [existing])
        let duplicate = ArchiveFile(
            originalFileName: "resume.txt",
            userDefinedName: "  RE\u{301}SUME\u{301}  ",
            detectedFormat: .plainText
        )

        do {
            try await repository.save(file: duplicate)
            XCTFail("Expected duplicate-name validation to fail")
        } catch {
            XCTAssertEqual(error as? ArchiveValidationError, .duplicateName)
        }
    }

    func testAssetSaveKeepsImmutableBytesForSession() async throws {
        let repository = InMemoryArchiveRepository()
        let file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            fileSize: 5,
            contentHash: "hash"
        )
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        try await repository.save(file: file, assetURL: sourceURL)
        try Data("changed".utf8).write(to: sourceURL)
        let storedURL = try await repository.fileContentURL(for: file.id)

        XCTAssertEqual(try Data(contentsOf: storedURL), Data("hello".utf8))
    }

    func testSnapshotHidesDescendantsOfTrashedFolderWithoutMutatingThem() async throws {
        let trashedRoot = ArchiveFolder(name: "Root", isTrashed: true, trashedAt: .now)
        let child = ArchiveFolder(name: "Child", parentFolderID: trashedRoot.id)
        let file = ArchiveFile(
            originalFileName: "nested.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            folders: [trashedRoot, child],
            files: [file]
        )

        let visible = await repository.fetchSnapshot()
        let trashedFolders = await repository.fetchTrashedFolders()

        XCTAssertTrue(visible.folders.isEmpty)
        XCTAssertTrue(visible.files.isEmpty)
        XCTAssertEqual(trashedFolders.map(\.id), [trashedRoot.id])
    }

    func testResetArchiveRemovesMetadataAssetsAndReportsCounts() async throws {
        let folder = ArchiveFolder(name: "Folder")
        let file = ArchiveFile(
            originalFileName: "note.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            folders: [folder],
            files: [file],
            assetDataByFileID: [file.id: Data("content".utf8)]
        )

        let result = await repository.resetArchive()
        let snapshot = await repository.fetchSnapshot()

        XCTAssertEqual(result, ArchiveResetResult(deletedFolderCount: 1, deletedFileCount: 1))
        XCTAssertTrue(snapshot.folders.isEmpty)
        XCTAssertTrue(snapshot.files.isEmpty)
        await XCTAssertThrowsErrorAsync {
            _ = try await repository.fileContentURL(for: file.id)
        }
    }

    func testPartialResetFailureReportsCompletedBoundary() {
        let error = ArchiveResetPartialFailure(
            deletedFolderCount: 3,
            deletedFileCount: 205,
            underlyingMessage: "Network unavailable."
        )

        XCTAssertEqual(
            error.errorDescription,
            "Deletion stopped after deleting 205 files and 3 folders. Network unavailable."
        )
    }

    func testRemoveIncompleteImportsDeletesOnlyRecordsThatNeverCompleted() async throws {
        let folder = ArchiveFolder(name: "Folder")
        let uploading = ArchiveFile(
            originalFileName: "uploading.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            importState: .uploading
        )
        let failed = ArchiveFile(
            originalFileName: "failed.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            importState: .failed
        )
        let completed = ArchiveFile(
            originalFileName: "completed.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText
        )
        let trashed = ArchiveFile(
            originalFileName: "trashed.txt",
            parentFolderID: folder.id,
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            folders: [folder],
            files: [uploading, failed, completed, trashed],
            assetDataByFileID: [
                uploading.id: Data("partial".utf8),
                completed.id: Data("keep".utf8)
            ]
        )

        let count = await repository.fetchIncompleteImportCount()
        let result = await repository.removeIncompleteImports()
        let remainingCount = await repository.fetchIncompleteImportCount()
        let snapshot = await repository.fetchSnapshot()
        let trashedFiles = await repository.fetchTrashedFiles()

        XCTAssertEqual(count, 2)
        XCTAssertEqual(result, IncompleteImportPurgeResult(deletedFileCount: 2))
        XCTAssertEqual(remainingCount, 0)
        XCTAssertEqual(snapshot.folders.map(\.id), [folder.id])
        XCTAssertEqual(snapshot.files.map(\.id), [completed.id])
        XCTAssertEqual(trashedFiles.map(\.id), [trashed.id])
        await XCTAssertThrowsErrorAsync {
            _ = try await repository.fileContentURL(for: uploading.id)
        }
        let completedURL = try await repository.fileContentURL(for: completed.id)
        XCTAssertEqual(try Data(contentsOf: completedURL), Data("keep".utf8))
    }

    func testPermanentlyDeletingTrashedFileRemovesItsAssetOnly() async throws {
        let trashedFile = ArchiveFile(
            originalFileName: "trashed.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText
        )
        let retainedFile = ArchiveFile(
            originalFileName: "retained.txt",
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            files: [trashedFile, retainedFile],
            assetDataByFileID: [
                trashedFile.id: Data("trash".utf8),
                retainedFile.id: Data("keep".utf8)
            ]
        )

        let result = try await repository.permanentlyDelete(.file(trashedFile))
        let snapshot = await repository.fetchSnapshot()

        XCTAssertEqual(result, ArchiveDeletionResult(deletedFolderCount: 0, deletedFileCount: 1))
        XCTAssertEqual(snapshot.files.map(\.id), [retainedFile.id])
        await XCTAssertThrowsErrorAsync {
            _ = try await repository.fileContentURL(for: trashedFile.id)
        }
        let retainedURL = try await repository.fileContentURL(for: retainedFile.id)
        XCTAssertEqual(try Data(contentsOf: retainedURL), Data("keep".utf8))
    }

    func testEmptyTrashDeletesTrashedFolderSubtreeAndExplicitTrashedFiles() async throws {
        let trashedFolder = ArchiveFolder(name: "Trashed", isTrashed: true, trashedAt: .now)
        let childFolder = ArchiveFolder(name: "Child", parentFolderID: trashedFolder.id)
        let nestedFile = ArchiveFile(
            originalFileName: "nested.txt",
            parentFolderID: childFolder.id,
            detectedFormat: .plainText
        )
        let explicitTrashedFile = ArchiveFile(
            originalFileName: "loose.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText
        )
        let retainedFile = ArchiveFile(originalFileName: "keep.txt", detectedFormat: .plainText)
        let repository = InMemoryArchiveRepository(
            folders: [trashedFolder, childFolder],
            files: [nestedFile, explicitTrashedFile, retainedFile]
        )

        let result = try await repository.emptyTrash()
        let snapshot = await repository.fetchSnapshot()
        let trashedFolders = await repository.fetchTrashedFolders()
        let trashedFiles = await repository.fetchTrashedFiles()

        XCTAssertEqual(result, ArchiveDeletionResult(deletedFolderCount: 2, deletedFileCount: 2))
        XCTAssertTrue(trashedFolders.isEmpty)
        XCTAssertTrue(trashedFiles.isEmpty)
        XCTAssertEqual(snapshot.files.map(\.id), [retainedFile.id])
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
