import CloudKit
import Foundation
import XCTest
@testable import ArchiveLeaf

final class CloudKitIntegrationTests: XCTestCase {
    func testDevelopmentDatabaseTrashPurge() async throws {
        #if !ARCHIVELEAF_CLOUDKIT_TRASH_PURGE_INTEGRATION
        throw XCTSkip("Destructive CloudKit Trash purge integration test is opt-in.")
        #else

        let repository = CloudKitArchiveRepository()
        _ = try await repository.resetArchive()

        let trashedRoot = ArchiveFolder(name: "Purge Root")
        let child = ArchiveFolder(name: "Purge Child", parentFolderID: trashedRoot.id)
        let content = Data("ArchiveLeaf Trash purge verification\n".utf8)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try content.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let hashFragment = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let nestedFile = ArchiveFile(
            originalFileName: "nested.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hashFragment + hashFragment
        )
        let looseFile = ArchiveFile(
            originalFileName: "loose.txt",
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: String((hashFragment + hashFragment).reversed())
        )

        try await repository.save(folder: trashedRoot)
        try await repository.save(folder: child)
        try await repository.save(file: nestedFile, assetURL: assetURL)
        try await repository.save(file: looseFile, assetURL: assetURL)

        var seededSnapshot = try await repository.fetchSnapshot()
        for _ in 0..<15 where seededSnapshot.folders.count != 2 || seededSnapshot.files.count != 2 {
            try await Task.sleep(for: .seconds(1))
            seededSnapshot = try await repository.fetchSnapshot()
        }
        XCTAssertEqual(seededSnapshot.folders.count, 2)
        XCTAssertEqual(seededSnapshot.files.count, 2)

        var trashedRootUpdate = trashedRoot
        trashedRootUpdate.isTrashed = true
        trashedRootUpdate.trashedAt = .now
        trashedRootUpdate.updatedAt = .now
        try await repository.save(folder: trashedRootUpdate)
        var looseFileUpdate = looseFile
        looseFileUpdate.isTrashed = true
        looseFileUpdate.trashedAt = .now
        looseFileUpdate.updatedAt = .now
        try await repository.save(file: looseFileUpdate)

        var remoteTrashedFolders = try await repository.fetchTrashedFolders()
        var remoteTrashedFiles = try await repository.fetchTrashedFiles()
        for _ in 0..<15 where
            !remoteTrashedFolders.contains(where: { $0.id == trashedRoot.id })
                || !remoteTrashedFiles.contains(where: { $0.id == looseFile.id }) {
            try await Task.sleep(for: .seconds(1))
            remoteTrashedFolders = try await repository.fetchTrashedFolders()
            remoteTrashedFiles = try await repository.fetchTrashedFiles()
        }

        let individualResult = try await repository.permanentlyDelete(.file(looseFileUpdate))
        XCTAssertEqual(individualResult, ArchiveDeletionResult(deletedFolderCount: 0, deletedFileCount: 1))
        let emptyResult = try await repository.emptyTrash()
        XCTAssertEqual(emptyResult, ArchiveDeletionResult(deletedFolderCount: 2, deletedFileCount: 1))
        let finalSnapshot = try await repository.fetchSnapshot()
        XCTAssertTrue(finalSnapshot.folders.isEmpty)
        XCTAssertTrue(finalSnapshot.files.isEmpty)
        do {
            _ = try await repository.fileContentURL(for: nestedFile.id)
            XCTFail("Expected the nested CloudKit asset record to be unavailable")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .unknownItem)
        }
        #endif
    }

    func testDevelopmentDatabaseIncompleteImportPurge() async throws {
        #if !ARCHIVELEAF_CLOUDKIT_INCOMPLETE_PURGE_INTEGRATION
        throw XCTSkip("Destructive CloudKit incomplete-import purge integration test is opt-in.")
        #else

        let repository = CloudKitArchiveRepository()
        _ = try await repository.resetArchive()

        let folder = ArchiveFolder(name: "Incomplete Purge Root")
        let content = Data("ArchiveLeaf incomplete import verification\n".utf8)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try content.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let hashFragment = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let completedFile = ArchiveFile(
            originalFileName: "completed.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hashFragment + hashFragment
        )
        let uploadingFile = ArchiveFile(
            originalFileName: "uploading.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: String((hashFragment + hashFragment).reversed()),
            importState: .uploading
        )

        try await repository.save(folder: folder)
        try await repository.save(file: completedFile, assetURL: assetURL)
        try await repository.save(file: uploadingFile, assetURL: assetURL)

        var incompleteCount = try await repository.fetchIncompleteImportCount()
        for _ in 0..<15 where incompleteCount != 1 {
            try await Task.sleep(for: .seconds(1))
            incompleteCount = try await repository.fetchIncompleteImportCount()
        }
        XCTAssertEqual(incompleteCount, 1)

        let result = try await repository.removeIncompleteImports()

        XCTAssertEqual(result, IncompleteImportPurgeResult(deletedFileCount: 1))
        XCTAssertEqual(try await repository.fetchIncompleteImportCount(), 0)
        let snapshot = try await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.folders.map(\.id), [folder.id])
        XCTAssertEqual(snapshot.files.map(\.id), [completedFile.id])
        let retainedAssetURL = try await repository.fileContentURL(for: completedFile.id)
        XCTAssertEqual(try Data(contentsOf: retainedAssetURL), content)
        do {
            _ = try await repository.fileContentURL(for: uploadingFile.id)
            XCTFail("Expected the incomplete CloudKit record to be unavailable")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .unknownItem)
        }

        _ = try await repository.resetArchive()
        #endif
    }

    func testDevelopmentDatabaseFullReset() async throws {
        #if !ARCHIVELEAF_CLOUDKIT_RESET_INTEGRATION
        throw XCTSkip("Destructive CloudKit reset integration test is opt-in.")
        #else

        let repository = CloudKitArchiveRepository()
        _ = try await repository.resetArchive()

        let folder = ArchiveFolder(name: "Reset Verification")
        let content = Data("ArchiveLeaf reset verification\n".utf8)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try content.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let hashFragment = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let file = ArchiveFile(
            originalFileName: "reset-verification.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hashFragment + hashFragment
        )

        let tag = ArchiveTag(name: "Reset Verification Tag")
        try await repository.save(tag: tag)
        try await repository.save(folder: folder)
        try await repository.save(file: file, assetURL: assetURL)
        let storedAssetURL = try await repository.fileContentURL(for: file.id)
        XCTAssertEqual(try Data(contentsOf: storedAssetURL), content)

        var seededSnapshot = try await repository.fetchSnapshot()
        for _ in 0..<15 where
            !seededSnapshot.folders.contains(where: { $0.id == folder.id })
                || !seededSnapshot.files.contains(where: { $0.id == file.id }) {
            try await Task.sleep(for: .seconds(1))
            seededSnapshot = try await repository.fetchSnapshot()
        }
        XCTAssertTrue(seededSnapshot.folders.contains(where: { $0.id == folder.id }))
        XCTAssertTrue(seededSnapshot.files.contains(where: { $0.id == file.id }))

        let result = try await repository.resetArchive()

        XCTAssertEqual(result, ArchiveResetResult(deletedFolderCount: 1, deletedFileCount: 1))
        let snapshot = try await repository.fetchSnapshot()
        let trashedFolders = try await repository.fetchTrashedFolders()
        let trashedFiles = try await repository.fetchTrashedFiles()
        XCTAssertTrue(snapshot.folders.isEmpty)
        XCTAssertTrue(snapshot.files.isEmpty)
        XCTAssertTrue(trashedFolders.isEmpty)
        XCTAssertTrue(trashedFiles.isEmpty)
        // Tags go with the archive. They used to stay, and a sweep on the next read covered for it.
        XCTAssertTrue(snapshot.tags.isEmpty)
        do {
            _ = try await repository.fileContentURL(for: file.id)
            XCTFail("Expected the deleted CloudKit asset record to be unavailable")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .unknownItem)
        }
        #endif
    }

    func testDevelopmentDatabaseAssetRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["ARCHIVELEAF_RUN_CLOUDKIT_INTEGRATION"] == "1" else {
            throw XCTSkip("CloudKit integration test is opt-in.")
        }

        let repository = CloudKitArchiveRepository()
        let folder = ArchiveFolder(name: "Development Seed")
        let childFolder = ArchiveFolder(
            name: "Nested Seed",
            parentFolderID: folder.id
        )
        // Unique per run so the duplicate lookup below matches only this seed, while still being
        // the real digest of the bytes: records whose hash does not describe their asset are
        // rejected by every path that verifies one, backup export included.
        let content = Data("ArchiveLeaf CloudKit development seed \(UUID().uuidString)\n".utf8)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try content.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        let file = ArchiveFile(
            originalFileName: "development-seed.txt",
            parentFolderID: childFolder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: try await SHA256FileContentHasher().sha256(for: assetURL)
        )

        try await repository.save(folder: folder)
        try await repository.save(folder: childFolder)
        try await repository.save(file: file, assetURL: assetURL)

        let downloadedURL = try await repository.fileContentURL(for: file.id)
        let downloadedContent = try Data(contentsOf: downloadedURL)
        let duplicateRepository = CloudKitArchiveRepository()
        var duplicateMatch = try await duplicateRepository
            .files(matchingContentHashes: [file.contentHash])[file.contentHash]
        for _ in 0..<10 where duplicateMatch == nil {
            try await Task.sleep(for: .seconds(1))
            duplicateMatch = try await duplicateRepository
                .files(matchingContentHashes: [file.contentHash])[file.contentHash]
        }
        var snapshot = try await repository.fetchSnapshot()
        for _ in 0..<10 where !snapshot.files.contains(where: { $0.id == file.id }) {
            try await Task.sleep(for: .seconds(1))
            snapshot = try await repository.fetchSnapshot()
        }

        XCTAssertTrue(snapshot.folders.contains(where: { $0.id == folder.id }))
        XCTAssertTrue(snapshot.folders.contains(where: { $0.id == childFolder.id }))
        XCTAssertTrue(snapshot.files.contains(where: { $0.id == file.id }))
        XCTAssertEqual(downloadedContent, content)
        XCTAssertEqual(duplicateMatch?.id, file.id)

        var trashedFile = file
        trashedFile.originalParentFolderID = file.parentFolderID
        trashedFile.isTrashed = true
        trashedFile.trashedAt = .now
        trashedFile.updatedAt = .now
        try await repository.save(file: trashedFile)

        let trashRepository = CloudKitArchiveRepository()
        var remoteTrashedFile: ArchiveFile?
        var activeAfterTrash = try await trashRepository.fetchSnapshot()
        for _ in 0..<15 where remoteTrashedFile == nil || activeAfterTrash.files.contains(where: { $0.id == file.id }) {
            try await Task.sleep(for: .seconds(1))
            remoteTrashedFile = try await trashRepository.fetchTrashedFiles().first(where: { $0.id == file.id })
            activeAfterTrash = try await trashRepository.fetchSnapshot()
        }

        let confirmedTrashedFile = try XCTUnwrap(remoteTrashedFile)
        let trashedAssetURL = try await trashRepository.fileContentURL(for: file.id)
        let trashedAssetContent = try Data(contentsOf: trashedAssetURL)
        XCTAssertFalse(activeAfterTrash.files.contains(where: { $0.id == file.id }))
        XCTAssertEqual(confirmedTrashedFile.originalParentFolderID, childFolder.id)
        XCTAssertEqual(trashedAssetContent, content)

        var restoredFile = confirmedTrashedFile
        restoredFile.parentFolderID = restoredFile.originalParentFolderID
        restoredFile.originalParentFolderID = nil
        restoredFile.isTrashed = false
        restoredFile.trashedAt = nil
        restoredFile.updatedAt = .now
        try await trashRepository.save(file: restoredFile)

        let restoredRepository = CloudKitArchiveRepository()
        var restoredSnapshot = try await restoredRepository.fetchSnapshot()
        var remainingTrash = try await restoredRepository.fetchTrashedFiles()
        for _ in 0..<15 where !restoredSnapshot.files.contains(where: { $0.id == file.id })
            || remainingTrash.contains(where: { $0.id == file.id }) {
            try await Task.sleep(for: .seconds(1))
            restoredSnapshot = try await restoredRepository.fetchSnapshot()
            remainingTrash = try await restoredRepository.fetchTrashedFiles()
        }

        let restoredAssetURL = try await restoredRepository.fileContentURL(for: file.id)
        let restoredAssetContent = try Data(contentsOf: restoredAssetURL)
        XCTAssertTrue(restoredSnapshot.files.contains(where: { $0.id == file.id }))
        XCTAssertFalse(remainingTrash.contains(where: { $0.id == file.id }))
        XCTAssertEqual(restoredAssetContent, content)

        var trashedFolder = folder
        trashedFolder.originalParentFolderID = folder.parentFolderID
        trashedFolder.isTrashed = true
        trashedFolder.trashedAt = .now
        trashedFolder.updatedAt = .now
        try await restoredRepository.save(folder: trashedFolder)

        let folderTrashRepository = CloudKitArchiveRepository()
        var activeAfterFolderTrash = try await folderTrashRepository.fetchSnapshot()
        var trashedFolders = try await folderTrashRepository.fetchTrashedFolders()
        for _ in 0..<15 where activeAfterFolderTrash.folders.contains(where: { $0.id == folder.id || $0.id == childFolder.id })
            || activeAfterFolderTrash.files.contains(where: { $0.id == file.id })
            || !trashedFolders.contains(where: { $0.id == folder.id }) {
            try await Task.sleep(for: .seconds(1))
            activeAfterFolderTrash = try await folderTrashRepository.fetchSnapshot()
            trashedFolders = try await folderTrashRepository.fetchTrashedFolders()
        }

        XCTAssertFalse(activeAfterFolderTrash.folders.contains(where: { $0.id == folder.id }))
        XCTAssertFalse(activeAfterFolderTrash.folders.contains(where: { $0.id == childFolder.id }))
        XCTAssertFalse(activeAfterFolderTrash.files.contains(where: { $0.id == file.id }))
        XCTAssertTrue(trashedFolders.contains(where: { $0.id == folder.id }))
        XCTAssertFalse(trashedFolders.contains(where: { $0.id == childFolder.id }))

        var restoredFolder = try XCTUnwrap(trashedFolders.first(where: { $0.id == folder.id }))
        restoredFolder.parentFolderID = restoredFolder.originalParentFolderID
        restoredFolder.originalParentFolderID = nil
        restoredFolder.isTrashed = false
        restoredFolder.trashedAt = nil
        restoredFolder.updatedAt = .now
        try await folderTrashRepository.save(folder: restoredFolder)

        let folderRestoreRepository = CloudKitArchiveRepository()
        var activeAfterFolderRestore = try await folderRestoreRepository.fetchSnapshot()
        var folderTrashAfterRestore = try await folderRestoreRepository.fetchTrashedFolders()
        for _ in 0..<15 where !activeAfterFolderRestore.folders.contains(where: { $0.id == folder.id })
            || !activeAfterFolderRestore.folders.contains(where: { $0.id == childFolder.id })
            || !activeAfterFolderRestore.files.contains(where: { $0.id == file.id })
            || folderTrashAfterRestore.contains(where: { $0.id == folder.id }) {
            try await Task.sleep(for: .seconds(1))
            activeAfterFolderRestore = try await folderRestoreRepository.fetchSnapshot()
            folderTrashAfterRestore = try await folderRestoreRepository.fetchTrashedFolders()
        }

        XCTAssertTrue(activeAfterFolderRestore.folders.contains(where: { $0.id == folder.id }))
        XCTAssertTrue(activeAfterFolderRestore.folders.contains(where: { $0.id == childFolder.id }))
        XCTAssertTrue(activeAfterFolderRestore.files.contains(where: { $0.id == file.id }))
        XCTAssertFalse(folderTrashAfterRestore.contains(where: { $0.id == folder.id }))

        let folderRestoredAssetURL = try await folderRestoreRepository.fileContentURL(for: file.id)
        XCTAssertEqual(try Data(contentsOf: folderRestoredAssetURL), content)
    }
}
