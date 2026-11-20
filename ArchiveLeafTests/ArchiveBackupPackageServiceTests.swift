import XCTest
@testable import ArchiveLeaf

final class ArchiveBackupPackageServiceTests: XCTestCase {
    func testExportsAndInspectsPackageWithoutTrash() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let content = Data("A reusable prompt".utf8)
        let sourceURL = workspace.appendingPathComponent("source.txt")
        try content.write(to: sourceURL)
        let hash = try await SHA256FileContentHasher().sha256(for: sourceURL)
        let folder = ArchiveFolder(name: "Prompts")
        let file = ArchiveFile(
            originalFileName: "source.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hash
        )
        let trashed = ArchiveFile(
            originalFileName: "discarded.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText,
            fileSize: 1,
            contentHash: "unused"
        )
        let repository = InMemoryArchiveRepository(
            folders: [folder],
            files: [file, trashed],
            assetDataByFileID: [file.id: content, trashed.id: Data("x".utf8)]
        )
        let service = ArchiveBackupPackageService(repository: repository)

        let exported = try await service.exportArchive(to: destination)
        let inspected = try await service.inspectBackup(at: destination)

        XCTAssertEqual(exported, inspected)
        XCTAssertEqual(inspected.folders.map(\.id), [folder.id])
        XCTAssertEqual(inspected.files.map(\.file.id), [file.id])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(inspected.files[0].assetRelativePath).path
        ))
    }

    func testRejectsTamperedAsset() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let original = Data("original".utf8)
        let sourceURL = workspace.appendingPathComponent("source.txt")
        try original.write(to: sourceURL)
        let hash = try await SHA256FileContentHasher().sha256(for: sourceURL)
        let file = ArchiveFile(
            originalFileName: "source.txt",
            detectedFormat: .plainText,
            fileSize: Int64(original.count),
            contentHash: hash
        )
        let repository = InMemoryArchiveRepository(
            files: [file],
            assetDataByFileID: [file.id: original]
        )
        let service = ArchiveBackupPackageService(repository: repository)
        let manifest = try await service.exportArchive(to: destination)
        let assetURL = destination.appendingPathComponent(manifest.files[0].assetRelativePath)
        try Data("modified".utf8).write(to: assetURL)

        do {
            _ = try await service.inspectBackup(at: destination)
            XCTFail("Expected tampered asset rejection")
        } catch {
            XCTAssertEqual(error as? ArchiveBackupPackageError, .assetHashMismatch(file.sidebarDisplayName))
        }
    }

    func testFailedExportDoesNotLeaveDestinationPackage() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let content = Data("content".utf8)
        let file = ArchiveFile(
            originalFileName: "source.txt",
            detectedFormat: .plainText,
            fileSize: Int64(content.count),
            contentHash: "incorrect"
        )
        let repository = InMemoryArchiveRepository(
            files: [file],
            assetDataByFileID: [file.id: content]
        )

        do {
            _ = try await ArchiveBackupPackageService(repository: repository)
                .exportArchive(to: destination)
            XCTFail("Expected checksum failure")
        } catch {
            XCTAssertEqual(error as? ArchiveBackupPackageError, .assetHashMismatch(file.sidebarDisplayName))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let remainingNames = try FileManager.default.contentsOfDirectory(atPath: workspace.path)
        XCTAssertTrue(remainingNames.isEmpty)
    }

    func testPrepareRestoreRequiresVisibleArchiveAndTrashToBeEmpty() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let packageURL = workspace.appendingPathComponent("Empty.albak")
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent(ArchiveBackupPackage.assetsDirectoryName),
            withIntermediateDirectories: true
        )
        let manifest = ArchiveBackupManifest(folders: [], files: [])
        try JSONArchiveBackupManifestCoder().encode(manifest).write(
            to: packageURL.appendingPathComponent(ArchiveBackupPackage.manifestFileName)
        )
        let trashed = ArchiveFile(
            originalFileName: "trash.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(files: [trashed])

        do {
            _ = try await ArchiveBackupPackageService(repository: repository)
                .prepareRestore(from: packageURL)
            XCTFail("Expected non-empty Archive rejection")
        } catch {
            XCTAssertEqual(error as? ArchiveBackupPackageError, .restoreRequiresEmptyArchive)
        }
    }

    func testPrepareRestoreAcceptsEmptyArchive() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let packageURL = workspace.appendingPathComponent("Empty.albak")
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent(ArchiveBackupPackage.assetsDirectoryName),
            withIntermediateDirectories: true
        )
        let manifest = ArchiveBackupManifest(folders: [], files: [])
        try JSONArchiveBackupManifestCoder().encode(manifest).write(
            to: packageURL.appendingPathComponent(ArchiveBackupPackage.manifestFileName)
        )

        let prepared = try await ArchiveBackupPackageService(
            repository: InMemoryArchiveRepository()
        ).prepareRestore(from: packageURL)

        XCTAssertEqual(prepared.manifest, manifest)
    }

    func testRestoreRebuildsHierarchyAndContentIntoAnEmptyArchive() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let content = Data("A reusable prompt".utf8)
        let sourceURL = workspace.appendingPathComponent("source.txt")
        try content.write(to: sourceURL)
        let hash = try await SHA256FileContentHasher().sha256(for: sourceURL)
        // Declared child-first so the restore has to order parents itself.
        let parent = ArchiveFolder(name: "Prompts")
        let child = ArchiveFolder(name: "Drafts", parentFolderID: parent.id)
        let file = ArchiveFile(
            originalFileName: "source.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hash
        )
        let source = InMemoryArchiveRepository(
            folders: [child, parent],
            files: [file],
            assetDataByFileID: [file.id: content]
        )
        _ = try await ArchiveBackupPackageService(repository: source).exportArchive(to: destination)

        let target = InMemoryArchiveRepository()
        let service = ArchiveBackupPackageService(repository: target)
        let result = try await service.restore(service.prepareRestore(from: destination))

        XCTAssertEqual(result.restoredFolderCount, 2)
        XCTAssertEqual(result.restoredFileCount, 1)
        let snapshot = await target.fetchSnapshot()
        XCTAssertEqual(Set(snapshot.folders.map(\.id)), [parent.id, child.id])
        XCTAssertEqual(snapshot.files.map(\.id), [file.id])
        XCTAssertEqual(snapshot.files.first?.parentFolderID, child.id)
        let restoredURL = try await target.fileContentURL(for: file.id)
        XCTAssertEqual(try Data(contentsOf: restoredURL), content)
    }

    func testExportedArchiveSurvivesARoundTripThroughRestore() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let content = Data("A reusable prompt".utf8)
        let sourceURL = workspace.appendingPathComponent("source.txt")
        try content.write(to: sourceURL)
        let hash = try await SHA256FileContentHasher().sha256(for: sourceURL)
        let folder = ArchiveFolder(name: "Prompts")
        let file = ArchiveFile(
            originalFileName: "source.txt",
            userDefinedName: "Reusable",
            parentFolderID: folder.id,
            isFavorite: true,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hash
        )
        let source = InMemoryArchiveRepository(
            folders: [folder],
            files: [file],
            assetDataByFileID: [file.id: content]
        )
        _ = try await ArchiveBackupPackageService(repository: source).exportArchive(to: destination)

        let target = InMemoryArchiveRepository()
        let targetService = ArchiveBackupPackageService(repository: target)
        _ = try await targetService.restore(targetService.prepareRestore(from: destination))

        let before = await source.fetchSnapshot()
        let after = await target.fetchSnapshot()
        XCTAssertEqual(before.folders, after.folders)
        XCTAssertEqual(before.files, after.files)
        let restoredURL = try await target.fileContentURL(for: file.id)
        XCTAssertEqual(try Data(contentsOf: restoredURL), content)
    }

    /// Every byte of the archive, read once on the way out and once on the way in.
    ///
    /// Both sides used to read it twice — export digested the source and then the copy it had just
    /// made, and restore digested the whole package again behind the reader's confirmation. Neither
    /// second pass could learn anything the first had not, and each doubled the cost of the one
    /// operation whose size is the whole archive. Counted here, because nothing else on screen
    /// shows the difference and a reinstated `prepareRestore` inside `restore` would look correct.
    func testEachAssetIsDigestedOncePerExportAndOncePerRestore() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let content = Data("A reusable prompt".utf8)
        let sourceURL = workspace.appendingPathComponent("source.txt")
        try content.write(to: sourceURL)
        let hash = try await SHA256FileContentHasher().sha256(for: sourceURL)
        let file = ArchiveFile(
            originalFileName: "source.txt",
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(content.count),
            contentHash: hash
        )
        let source = InMemoryArchiveRepository(files: [file], assetDataByFileID: [file.id: content])

        let exportCounter = CountingFileContentHasher()
        _ = try await ArchiveBackupPackageService(repository: source, hasher: exportCounter)
            .exportArchive(to: destination)
        let exportCount = await exportCounter.count
        XCTAssertEqual(exportCount, 1)

        let restoreCounter = CountingFileContentHasher()
        let service = ArchiveBackupPackageService(
            repository: InMemoryArchiveRepository(),
            hasher: restoreCounter
        )
        _ = try await service.restore(service.prepareRestore(from: destination))
        let restoreCount = await restoreCounter.count
        XCTAssertEqual(restoreCount, 1)
    }

    /// A restore that stops part-way says how far it got, and the number is the archive's, not the
    /// batch's.
    ///
    /// The counting moved when the writes became batched: it used to be a `+= 1` in the loop that
    /// wrote each record, and it is now whatever the repository reports having accepted. A count
    /// taken from the size of the batch instead would name a boundary that is not there, and the
    /// message it appears in tells the reader what state their archive is in.
    func testRestoreStoppedPartWayReportsWhatWasWritten() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let destination = workspace.appendingPathComponent("Shelf.albak")
        let folder = ArchiveFolder(name: "Prompts")
        var files: [ArchiveFile] = []
        var assets: [UUID: Data] = [:]
        for index in 0..<4 {
            let content = Data("payload \(index)".utf8)
            let assetURL = workspace.appendingPathComponent("source\(index).txt")
            try content.write(to: assetURL)
            let file = ArchiveFile(
                originalFileName: "source\(index).txt",
                parentFolderID: folder.id,
                detectedFormat: .plainText,
                fileSize: Int64(content.count),
                contentHash: try await SHA256FileContentHasher().sha256(for: assetURL)
            )
            files.append(file)
            assets[file.id] = content
        }
        let source = InMemoryArchiveRepository(
            folders: [folder],
            files: files,
            assetDataByFileID: assets
        )
        _ = try await ArchiveBackupPackageService(repository: source).exportArchive(to: destination)

        let target = FailingAfterNFilesRepository(acceptedFileCount: 2)
        let service = ArchiveBackupPackageService(repository: target)

        do {
            _ = try await service.restore(service.prepareRestore(from: destination))
            XCTFail("Expected the restore to stop")
        } catch let failure as ArchiveBackupRestorePartialFailure {
            XCTAssertEqual(failure.restoredFolderCount, 1)
            XCTAssertEqual(failure.restoredFileCount, 2)
        }
    }

    /// A plan is not a promise that the archive is still empty. It is made while the reader is
    /// being asked to confirm, and another device can write in that gap, so the emptiness is asked
    /// again on the way in — this is the one check `restore` still repeats.
    func testRestoreRefusesAnArchiveFilledAfterThePlanWasMade() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let packageURL = workspace.appendingPathComponent("Empty.albak")
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent(ArchiveBackupPackage.assetsDirectoryName),
            withIntermediateDirectories: true
        )
        try JSONArchiveBackupManifestCoder().encode(
            ArchiveBackupManifest(folders: [], files: [])
        ).write(to: packageURL.appendingPathComponent(ArchiveBackupPackage.manifestFileName))
        let repository = InMemoryArchiveRepository()
        let service = ArchiveBackupPackageService(repository: repository)

        let plan = try await service.prepareRestore(from: packageURL)
        try await repository.save(folder: ArchiveFolder(name: "Existing"))

        do {
            _ = try await service.restore(plan)
            XCTFail("Expected restore to require an empty archive")
        } catch {
            XCTAssertEqual(error as? ArchiveBackupPackageError, .restoreRequiresEmptyArchive)
        }
    }

    func testPartialRestoreFailureReportsWhatWasAlreadyWritten() throws {
        let error = ArchiveBackupRestorePartialFailure(
            restoredFolderCount: 2,
            restoredFileCount: 17,
            underlyingMessage: "Network unavailable."
        )

        // Asserted by content rather than by exact wording: the description is localized, so the
        // surrounding sentence differs by language while the boundary it reports must not.
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("2"), message)
        XCTAssertTrue(message.contains("17"), message)
        XCTAssertTrue(message.contains("Network unavailable."), message)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeafBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

/// Counts the digests taken, and answers each one honestly so the operation under test still runs
/// to completion.
private actor CountingFileContentHasher: FileContentHashing {
    private(set) var count = 0

    func sha256(for url: URL) async throws -> String {
        count += 1
        return try await SHA256FileContentHasher().sha256(for: url)
    }
}

/// An archive that accepts a fixed number of files and then refuses. Everything else is the
/// in-memory repository's, including the batched-write default, which is the path under test.
private actor FailingAfterNFilesRepository: ArchiveRepository {
    private let backing = InMemoryArchiveRepository()
    private let acceptedFileCount: Int
    private var savedFileCount = 0

    init(acceptedFileCount: Int) {
        self.acceptedFileCount = acceptedFileCount
    }

    func fetchSnapshot() async throws -> ArchiveSnapshot { await backing.fetchSnapshot() }
    func fetchTrashedFiles() async throws -> [ArchiveFile] { await backing.fetchTrashedFiles() }
    func fetchTrashedFolders() async throws -> [ArchiveFolder] { await backing.fetchTrashedFolders() }
    func fileContentURL(for fileID: UUID) async throws -> URL {
        try await backing.fileContentURL(for: fileID)
    }
    func save(folder: ArchiveFolder) async throws { try await backing.save(folder: folder) }
    func save(tag: ArchiveTag) async throws { await backing.save(tag: tag) }
    func delete(tag: ArchiveTag) async throws { await backing.delete(tag: tag) }

    func save(file: ArchiveFile) async throws {
        guard savedFileCount < acceptedFileCount else { throw ArchiveLeafError.unreadableFile }
        savedFileCount += 1
        try await backing.save(file: file)
    }

    func save(file: ArchiveFile, assetURL: URL) async throws {
        guard savedFileCount < acceptedFileCount else { throw ArchiveLeafError.unreadableFile }
        savedFileCount += 1
        try await backing.save(file: file, assetURL: assetURL)
    }
}
