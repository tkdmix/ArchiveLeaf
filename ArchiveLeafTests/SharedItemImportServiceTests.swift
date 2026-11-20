import Foundation
import XCTest
@testable import ArchiveLeaf

final class SharedItemImportServiceTests: XCTestCase {
    func testImportsAtTheRootPresentedAsUnsortedFiles() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fileURL = workspace.appendingPathComponent("note.txt")
        try Data("shared".utf8).write(to: fileURL)
        let repository = InMemoryArchiveRepository()

        let result = try await SharedItemImportService(repository: repository).importFiles(at: [fileURL])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.wasCancelled)
        let snapshot = await repository.fetchSnapshot()
        XCTAssertTrue(snapshot.folders.isEmpty)
        XCTAssertTrue(snapshot.files.allSatisfy { $0.parentFolderID == nil })
    }

    func testDoesNotConfuseAnExistingUnsortedFolderWithTheRoot() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let existingFolder = ArchiveFolder(name: "Unsorted")
        let existingFile = ArchiveFile(
            originalFileName: "earlier.txt",
            parentFolderID: existingFolder.id,
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            folders: [existingFolder],
            files: [existingFile],
            assetDataByFileID: [existingFile.id: Data("earlier".utf8)]
        )
        let fileURL = workspace.appendingPathComponent("later.txt")
        try Data("later".utf8).write(to: fileURL)

        _ = try await SharedItemImportService(repository: repository).importFiles(at: [fileURL])

        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.folders.count, 1)
        let added = try XCTUnwrap(snapshot.files.first { $0.originalFileName == "later.txt" })
        XCTAssertNil(added.parentFolderID)
    }

    func testReportsRejectionsWithoutStoppingTheRest() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let good = workspace.appendingPathComponent("good.txt")
        try Data("keep".utf8).write(to: good)
        // A ZIP signature: recognized, and refused with an explanation.
        let archive = workspace.appendingPathComponent("bundle.zip")
        try Data([0x50, 0x4B, 0x03, 0x04] + Array(repeating: 0, count: 26)).write(to: archive)

        let result = try await SharedItemImportService(repository: InMemoryArchiveRepository())
            .importFiles(at: [good, archive])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.failures.map(\.sourceURL.lastPathComponent), ["bundle.zip"])
    }

    @MainActor
    func testProgressIncludesPreflightRejectionsInItsTotal() async throws {
        let acceptedURL = URL(fileURLWithPath: "/tmp/accepted.txt")
        let rejectedURL = URL(fileURLWithPath: "/tmp/rejected.zip")
        let candidate = importCandidate(for: acceptedURL)
        let preflight = SharedStaticPreflight(
            candidates: [candidate],
            failures: [ImportFailure(sourceURL: rejectedURL, reason: "Unsupported")]
        )
        var updates: [(completed: Int, total: Int)] = []

        let result = try await SharedItemImportService(
            repository: InMemoryArchiveRepository(),
            preflight: preflight,
            importer: SharedSuccessfulImporter()
        ).importFiles(at: [acceptedURL, rejectedURL]) { progress in
            updates.append((progress.completed, progress.total))
        }

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.completed, 2)
        XCTAssertEqual(updates.first?.total, 2)
    }

    func testContinuesAfterOneCandidateFailsToImport() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let failedURL = URL(fileURLWithPath: "/tmp/failed.txt")
        let lastURL = URL(fileURLWithPath: "/tmp/last.txt")
        let candidates = [firstURL, failedURL, lastURL].map { importCandidate(for: $0) }

        let result = try await SharedItemImportService(
            repository: InMemoryArchiveRepository(),
            preflight: SharedStaticPreflight(candidates: candidates),
            importer: SharedSelectiveImporter(failingName: failedURL.lastPathComponent)
        ).importFiles(at: [firstURL, failedURL, lastURL])

        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.failures.map(\.sourceURL), [failedURL])
        XCTAssertFalse(result.wasCancelled)
    }

    /// Cancelling during the write says so, and claims nothing. The write is one piece of work now,
    /// so there is no "stopped between two files" to report — the archive either took the batch or
    /// did not.
    func testCancellationDuringTheWriteIsReported() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        let candidates = [firstURL, secondURL].map { importCandidate(for: $0) }
        let importer = SharedCancellationImporter()
        let service = SharedItemImportService(
            repository: InMemoryArchiveRepository(),
            preflight: SharedStaticPreflight(candidates: candidates),
            importer: importer
        )

        let task = Task {
            try await service.importFiles(at: [firstURL, secondURL])
        }
        while await importer.importCount == 0 {
            await Task.yield()
        }
        task.cancel()

        let result = try await task.value
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.wasCancelled)
        let importCount = await importer.importCount
        XCTAssertEqual(importCount, 2)
    }

    func testImportsAStagedBookmarkWithoutFetchingItsPage() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let webURL = try XCTUnwrap(URL(string: "https://example.com/shared"))
        let bookmark = try BookmarkDocument.write(url: webURL, title: "Shared Page", into: workspace)
        let repository = InMemoryArchiveRepository()

        let result = try await SharedItemImportService(repository: repository)
            .importFiles(at: [bookmark])

        XCTAssertEqual(result.importedCount, 1)
        let snapshot = await repository.fetchSnapshot()
        let file = try XCTUnwrap(snapshot.files.first)
        XCTAssertEqual(file.originalFileName, "Shared Page.webloc")
        XCTAssertEqual(file.detectedFormat, .bookmark)
        XCTAssertNil(file.parentFolderID)
        let storedURL = try await repository.fileContentURL(for: file.id)
        XCTAssertEqual(try BookmarkDocument.url(from: Data(contentsOf: storedURL)), webURL)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedItemImportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func importCandidate(for url: URL) -> ImportCandidate {
        ImportCandidate(
            sourceURL: url,
            detection: .viewable(format: .plainText, sourceEncoding: "utf-8"),
            fileSize: 1,
            sourceModifiedAt: nil,
            contentHash: url.lastPathComponent
        )
    }
}

private struct SharedStaticPreflight: ImportPreflightChecking {
    let candidates: [ImportCandidate]
    var failures: [ImportFailure] = []

    func inspect(urls: [URL]) -> ImportPreflightResult {
        ImportPreflightResult(candidates: candidates, failures: failures)
    }
}

private struct SharedSuccessfulImporter: ArchiveImporting {
    func importFiles(_ placements: [ImportPlacement]) -> ArchiveImportOutcome {
        ArchiveImportOutcome(
            importedFiles: placements.map(SharedTestImportedFile.make),
            failures: []
        )
    }
}

private struct SharedSelectiveImporter: ArchiveImporting {
    let failingName: String

    func importFiles(_ placements: [ImportPlacement]) -> ArchiveImportOutcome {
        var imported: [ArchiveFile] = []
        var failures: [ImportFailure] = []
        for placement in placements {
            if placement.candidate.sourceURL.lastPathComponent == failingName {
                failures.append(ImportFailure(
                    sourceURL: placement.candidate.sourceURL,
                    reason: "failed"
                ))
            } else {
                imported.append(SharedTestImportedFile.make(placement))
            }
        }
        return ArchiveImportOutcome(importedFiles: imported, failures: failures)
    }
}

private actor SharedCancellationImporter: ArchiveImporting {
    private(set) var importCount = 0

    func importFiles(_ placements: [ImportPlacement]) async -> ArchiveImportOutcome {
        importCount += placements.count
        while !Task.isCancelled {
            await Task.yield()
        }
        return ArchiveImportOutcome(importedFiles: [], failures: [])
    }
}

private enum SharedTestImportedFile {
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

private enum SharedImportTestError: Error {
    case failed
}
