import Foundation
import XCTest
@testable import ArchiveLeaf

final class SHA256DuplicateDetectorTests: XCTestCase {
    func testComputesStableLowercaseSHA256() async throws {
        let url = try temporaryFile(Data("ArchiveLeaf".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let detector = SHA256DuplicateDetector(lookup: StubDuplicateLookup())

        let hash = try await detector.contentHash(for: url)

        XCTAssertEqual(hash, "cd2037bc42c523ef8d951d1ab1da8a93ee4efd0540bdc66170fd78faf32caaeb")
    }

    func testFindsCompletedFileInTrash() async throws {
        let hash = String(repeating: "a", count: 64)
        let file = ArchiveFile(
            originalFileName: "trashed.txt",
            isTrashed: true,
            trashedAt: .now,
            detectedFormat: .plainText,
            contentHash: hash
        )
        let repository = InMemoryArchiveRepository(files: [file])
        let detector = SHA256DuplicateDetector(lookup: repository)

        let matches = try await detector.existingFiles(matchingContentHashes: [hash.uppercased()])

        XCTAssertEqual(matches[hash]?.id, file.id)
        XCTAssertEqual(matches[hash]?.isTrashed, true)
    }

    func testIgnoresIncompleteMatchingFile() async throws {
        let hash = String(repeating: "b", count: 64)
        let file = ArchiveFile(
            originalFileName: "uploading.txt",
            detectedFormat: .plainText,
            contentHash: hash,
            importState: .uploading
        )
        let repository = InMemoryArchiveRepository(files: [file])
        let detector = SHA256DuplicateDetector(lookup: repository)

        let matches = try await detector.existingFiles(matchingContentHashes: [hash])

        XCTAssertTrue(matches.isEmpty)
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}

private actor StubDuplicateLookup: DuplicateFileLookingUp {
    func files(matchingContentHashes hashes: Set<String>) -> [String: ArchiveFile] { [:] }
}
