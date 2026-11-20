import Foundation
import XCTest
@testable import ArchiveLeaf

final class DiskArchiveSnapshotCacheTests: XCTestCase {
    func testRoundTripsAndRemovesSnapshot() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let cache = DiskArchiveSnapshotCache(fileURL: fileURL)
        let folder = ArchiveFolder(name: "Offline")
        let file = ArchiveFile(
            originalFileName: "cached.txt",
            parentFolderID: folder.id,
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: 12,
            contentHash: "hash"
        )
        let snapshot = ArchiveSnapshot(folders: [folder], files: [file])

        try await cache.storeSnapshot(snapshot)
        let loaded = try await cache.loadSnapshot()

        XCTAssertEqual(loaded?.folders, [folder])
        XCTAssertEqual(loaded?.files, [file])

        try await cache.removeSnapshot()
        let removed = try await cache.loadSnapshot()
        XCTAssertNil(removed)
    }
}
