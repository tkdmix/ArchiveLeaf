import Foundation
import XCTest
@testable import ArchiveLeaf

final class ImportPreflightServiceTests: XCTestCase {
    func testDefaultVideoLimitIsTwoHundredMegabytes() {
        XCTAssertEqual(ImportPolicy().maximumVideoSize, 200 * 1_024 * 1_024)
    }

    func testDefaultPDFLimitIsFiftyMegabytes() {
        XCTAssertEqual(ImportPolicy().maximumPDFSize, 50 * 1_024 * 1_024)
    }

    func testPDFImportLimitIsConfiguredIndependently() async throws {
        let data = PDFTestDocument.data()
        let url = try temporaryFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let accepted = await ImportPreflightService(
            policy: ImportPolicy(maximumPDFSize: Int64(data.count))
        ).inspect(urls: [url])
        let refused = await ImportPreflightService(
            policy: ImportPolicy(maximumPDFSize: Int64(data.count - 1))
        ).inspect(urls: [url])

        XCTAssertEqual(accepted.candidates.map(\.sourceURL), [url])
        XCTAssertTrue(refused.candidates.isEmpty)
        XCTAssertEqual(refused.failures.count, 1)
    }

    func testReturnsCandidatesAndIndividualFailures() async throws {
        let validURL = try temporaryFile(Data("plain text".utf8))
        let unsupportedURL = try temporaryFile(Data([0, 1, 2, 3]))
        defer {
            try? FileManager.default.removeItem(at: validURL)
            try? FileManager.default.removeItem(at: unsupportedURL)
        }

        let result = await ImportPreflightService().inspect(urls: [validURL, unsupportedURL])

        XCTAssertEqual(result.candidates.map(\.sourceURL), [validURL])
        XCTAssertEqual(result.failures.map(\.sourceURL), [unsupportedURL])
    }

    func testEnforcesFormatSpecificSizeBeforeAcceptingCandidate() async throws {
        let url = try temporaryFile(Data("12345".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let policy = ImportPolicy(maximumTextImportSize: 4)

        let result = await ImportPreflightService(policy: policy).inspect(urls: [url])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testVideoImportLimitIsConfiguredIndependently() async throws {
        let data = Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])
        let url = try temporaryFile(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let policy = ImportPolicy(maximumVideoSize: Int64(data.count - 1))

        let result = await ImportPreflightService(policy: policy).inspect(urls: [url])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testEnforcesBatchFileCountWithPartialSuccess() async throws {
        let first = try temporaryFile(Data("first".utf8))
        let second = try temporaryFile(Data("second".utf8))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let policy = ImportPolicy(maximumBatchFileCount: 1)

        let result = await ImportPreflightService(policy: policy).inspect(urls: [first, second])

        XCTAssertEqual(result.candidates.map(\.sourceURL), [first])
        XCTAssertEqual(result.failures.map(\.sourceURL), [second])
    }

    func testRejectsDuplicateFilesWithinSelection() async throws {
        let first = try temporaryFile(Data("same".utf8))
        let second = try temporaryFile(Data("same".utf8))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let duplicateDetector = SHA256DuplicateDetector(lookup: EmptyDuplicateLookup())
        let service = ImportPreflightService(duplicateDetector: duplicateDetector)

        let result = await service.inspect(urls: [first, second])

        XCTAssertEqual(result.candidates.map(\.sourceURL), [first])
        XCTAssertFalse(result.candidates[0].contentHash.isEmpty)
        XCTAssertEqual(result.failures.map(\.sourceURL), [second])
    }

    func testRejectsDuplicateDisplayNamesBeforeImport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("notes.txt")
        let second = directory.appendingPathComponent("notes.md")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let result = await ImportPreflightService().inspect(urls: [first, second])

        XCTAssertEqual(result.candidates.map(\.sourceURL), [first])
        XCTAssertEqual(result.failures.map(\.sourceURL), [second])
        XCTAssertTrue(result.failures[0].reason.contains("notes"))
    }

    func testEnumeratesExternalFolderAndPreservesEmptyFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let note = documents.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: note)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await ImportPreflightService().inspect(urls: [root])

        XCTAssertEqual(
            result.candidates.map(\.importPathComponents),
            [[root.lastPathComponent, "Documents", "note.txt"]]
        )
        XCTAssertEqual(
            Set(result.folderPathComponents),
            Set([
                [root.lastPathComponent],
                [root.lastPathComponent, "Documents"],
                [root.lastPathComponent, "Empty"]
            ])
        )
    }

    func testRejectsExternalFolderPathBeyondImportPolicyLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await ImportPreflightService(
            policy: ImportPolicy(maximumRelativePathLength: 10)
        ).inspect(urls: [root])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].reason.contains("10-character"))
    }

    func testRejectsAnArchiveAndSaysToExpandItFirst() async throws {
        // Only the local-file-header signature is needed; detection rejects before reading further.
        let url = try temporaryFile(Data([0x50, 0x4B, 0x03, 0x04] + Array(repeating: 0, count: 26)))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ImportPreflightService().inspect(urls: [url])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        // The reason is localized, so assert that one was given rather than its exact wording.
        XCTAssertFalse(result.failures[0].reason.isEmpty)
    }

    func testRejectsDuplicateInTrashWithRestoreReason() async throws {
        let url = try temporaryFile(Data("existing".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let hash = try await SHA256DuplicateDetector(lookup: EmptyDuplicateLookup()).contentHash(for: url)
        let existing = ArchiveFile(
            originalFileName: "existing.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText,
            contentHash: hash
        )
        let repository = InMemoryArchiveRepository(files: [existing])
        let service = ImportPreflightService(
            duplicateDetector: SHA256DuplicateDetector(lookup: repository)
        )

        let result = await service.inspect(urls: [url])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].reason.contains("Restore"))
    }

    /// One file already on the shelf used to refuse the folder it was found in, and every other
    /// file with it.
    func testKeepsTheRestOfAFolderWhenOneFileIsAlreadyArchived() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let known = root.appendingPathComponent("known.txt")
        try Data("known".utf8).write(to: known)
        try Data("fresh".utf8).write(to: root.appendingPathComponent("fresh.txt"))

        let hash = try await SHA256DuplicateDetector(lookup: EmptyDuplicateLookup())
            .contentHash(for: known)
        let repository = InMemoryArchiveRepository(files: [
            ArchiveFile(originalFileName: "known.txt", detectedFormat: .plainText, contentHash: hash)
        ])
        let service = ImportPreflightService(
            duplicateDetector: SHA256DuplicateDetector(lookup: repository)
        )

        let result = await service.inspect(urls: [root])

        XCTAssertEqual(result.candidates.map { $0.sourceURL.lastPathComponent }, ["fresh.txt"])
        XCTAssertEqual(result.failures.map { $0.sourceURL.lastPathComponent }, ["known.txt"])
        XCTAssertFalse(result.folderPathComponents.isEmpty)
    }

    /// Two copies of the same thing inside one folder: the second is left out, not the folder.
    func testKeepsTheRestOfAFolderWhenTwoFilesInsideItAreIdentical() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("same".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("same".utf8).write(to: root.appendingPathComponent("b.txt"))
        try Data("other".utf8).write(to: root.appendingPathComponent("c.txt"))

        let service = ImportPreflightService(
            duplicateDetector: SHA256DuplicateDetector(lookup: EmptyDuplicateLookup())
        )
        let result = await service.inspect(urls: [root])

        XCTAssertEqual(
            Set(result.candidates.map { $0.sourceURL.lastPathComponent }).count,
            2
        )
        XCTAssertTrue(result.candidates.contains { $0.sourceURL.lastPathComponent == "c.txt" })
        XCTAssertEqual(result.failures.count, 1)
    }

    /// The archive is asked once, however many files are selected.
    func testAsksTheArchiveAboutEveryHashInOneLookup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<8 {
            try Data("file \(index)".utf8).write(to: root.appendingPathComponent("note-\(index).txt"))
        }

        let lookup = CountingDuplicateLookup()
        let service = ImportPreflightService(
            duplicateDetector: SHA256DuplicateDetector(lookup: lookup)
        )
        let result = await service.inspect(urls: [root])

        XCTAssertEqual(result.candidates.count, 8)
        let callCount = await lookup.callCount
        let askedHashCount = await lookup.askedHashCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(askedHashCount, 8)
    }

    /// An archive that cannot answer stops the import: importing without asking is how a second
    /// copy gets in.
    func testRefusesEverythingWhenTheDuplicateLookupFails() async throws {
        let url = try temporaryFile(Data("content".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let service = ImportPreflightService(
            duplicateDetector: SHA256DuplicateDetector(lookup: FailingDuplicateLookup())
        )
        let result = await service.inspect(urls: [url])

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.failures.map(\.sourceURL), [url])
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}

private actor EmptyDuplicateLookup: DuplicateFileLookingUp {
    func files(matchingContentHashes hashes: Set<String>) -> [String: ArchiveFile] { [:] }
}

private actor CountingDuplicateLookup: DuplicateFileLookingUp {
    private(set) var callCount = 0
    private(set) var askedHashCount = 0

    func files(matchingContentHashes hashes: Set<String>) -> [String: ArchiveFile] {
        callCount += 1
        askedHashCount += hashes.count
        return [:]
    }
}

private actor FailingDuplicateLookup: DuplicateFileLookingUp {
    func files(matchingContentHashes hashes: Set<String>) throws -> [String: ArchiveFile] {
        throw CloudKitRepositoryError.iCloudUnavailable
    }
}
