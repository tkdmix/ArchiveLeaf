import Foundation
import XCTest
@testable import ArchiveLeaf

final class ArchiveImportServiceTests: XCTestCase {
    /// One write, carrying the payload, already complete. The empty placeholder record that used to
    /// go first cost two round trips a file and was the only reason an interrupted import left
    /// records no screen could show.
    func testWritesEachFileOnceWithItsPayloadAlreadyCompleted() async throws {
        let repository = ImportRecordingRepository()
        let service = ArchiveImportService(repository: repository)
        let first = try temporaryFile(contents: "one")
        let second = try temporaryFile(contents: "two")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let outcome = await service.importFiles([
            placement(first, hash: "hash-one"),
            placement(second, hash: "hash-two")
        ])

        let batches = await repository.batches
        XCTAssertEqual(outcome.importedFiles.count, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        // Everything selected went in one request, not one each.
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].map(\.state), [.completed, .completed])
        XCTAssertEqual(batches[0].map(\.assetURL), [first, second])
    }

    func testReportsARefusedFileByNameAndKeepsTheRest() async throws {
        let good = try temporaryFile(contents: "good")
        let bad = try temporaryFile(contents: "bad")
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }
        let repository = ImportRecordingRepository(failingAssetURL: bad)
        let service = ArchiveImportService(repository: repository)

        let outcome = await service.importFiles([
            placement(good, hash: "hash-good"),
            placement(bad, hash: "hash-bad")
        ])

        XCTAssertEqual(outcome.importedFiles.map(\.originalFileName), [good.lastPathComponent])
        XCTAssertEqual(outcome.failures.map(\.sourceURL), [bad])
    }

    func testRejectsZIPWithoutWritingAnything() async throws {
        let repository = ImportRecordingRepository()
        let service = ArchiveImportService(repository: repository)
        let url = try temporaryFile(contents: "zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = await service.importFiles([
            ImportPlacement(
                candidate: ImportCandidate(
                    sourceURL: url,
                    detection: .zipArchive,
                    fileSize: 3,
                    sourceModifiedAt: nil,
                    contentHash: "hash"
                ),
                folderID: nil
            )
        ])

        let batches = await repository.batches
        XCTAssertTrue(outcome.importedFiles.isEmpty)
        XCTAssertEqual(outcome.failures.map(\.sourceURL), [url])
        XCTAssertTrue(batches.isEmpty)
    }

    private func placement(_ url: URL, hash: String) -> ImportPlacement {
        ImportPlacement(
            candidate: ImportCandidate(
                sourceURL: url,
                detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
                fileSize: 3,
                sourceModifiedAt: nil,
                contentHash: hash
            ),
            folderID: nil
        )
    }

    private func temporaryFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(contents.utf8).write(to: url)
        return url
    }
}

private actor ImportRecordingRepository: ArchiveRepository {
    struct Write: Sendable {
        let state: ImportState
        let assetURL: URL
    }

    private(set) var batches: [[Write]] = []
    private let failingAssetURL: URL?

    init(failingAssetURL: URL? = nil) {
        self.failingAssetURL = failingAssetURL
    }

    func fetchSnapshot() -> ArchiveSnapshot { ArchiveSnapshot(folders: [], files: []) }
    func fetchTrashedFiles() -> [ArchiveFile] { [] }
    func fetchTrashedFolders() -> [ArchiveFolder] { [] }
    func fileContentURL(for fileID: UUID) throws -> URL { throw ArchiveLeafError.notImplemented }
    func save(folder: ArchiveFolder) {}
    func save(tag: ArchiveTag) {}
    func delete(tag: ArchiveTag) {}
    func save(file: ArchiveFile) {}
    func save(file: ArchiveFile, assetURL: URL) {}

    func create(files: [ArchiveFileAsset]) -> [UUID: any Error] {
        batches.append(files.map { Write(state: $0.file.importState, assetURL: $0.assetURL) })
        var failures: [UUID: any Error] = [:]
        for entry in files where entry.assetURL == failingAssetURL {
            failures[entry.file.id] = TestImportError.assetSaveFailed
        }
        return failures
    }
}

private enum TestImportError: Error {
    case assetSaveFailed
}
