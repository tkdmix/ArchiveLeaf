import CloudKit
import Foundation
import XCTest
@testable import ArchiveLeaf

/// How long a bulk edit takes against the real archive, and what it is spending the time on.
///
/// Opt-in at compile time, like the Trash purge test, because it writes: it makes its own files,
/// times the write path the selection bar uses, and takes them away again. Nothing already in the
/// archive is touched.
///
///   xcodebuild test -project ArchiveLeaf.xcodeproj -scheme ArchiveLeaf \
///     -destination 'platform=macOS' \
///     -only-testing:ArchiveLeafTests/BulkWriteBenchmark \
///     OTHER_SWIFT_FLAGS='-D ARCHIVELEAF_BULK_BENCHMARK'
final class BulkWriteBenchmark: XCTestCase {
    /// Enough to see the cost grow, few enough that a slow run is still a minute rather than ten.
    private let fileCount = 20

    func testFavoritingManyFiles() async throws {
        #if !ARCHIVELEAF_BULK_BENCHMARK
        throw XCTSkip("Bulk write benchmark is opt-in: pass -D ARCHIVELEAF_BULK_BENCHMARK.")
        #else
        let repository = CloudKitArchiveRepository()
        let folder = ArchiveFolder(name: "Benchmark \(UUID().uuidString.prefix(8))")
        try await repository.save(folder: folder)

        var files: [ArchiveFile] = []
        let creationStart = Date()
        for index in 0..<fileCount {
            let hash = String(repeating: String(format: "%02x", index % 256), count: 32)
            let file = ArchiveFile(
                originalFileName: "benchmark-\(index).txt",
                parentFolderID: folder.id,
                detectedFormat: .plainText,
                sourceEncoding: "utf-8",
                fileSize: 0,
                contentHash: hash
            )
            try await repository.save(file: file)
            files.append(file)
        }
        let creation = Date().timeIntervalSince(creationStart)
        print("BENCH created \(fileCount) files in \(ms(creation)) ms (\(ms(creation / Double(fileCount))) ms each)")

        // The old path, kept so the two can be compared in the same run and on the same network:
        // one file at a time, each waiting for the last.
        var oneAtATime = files
        let sequentialStart = Date()
        for index in oneAtATime.indices {
            oneAtATime[index].isFavorite = true
            oneAtATime[index].updatedAt = .now
            try await repository.save(file: oneAtATime[index])
        }
        let sequential = Date().timeIntervalSince(sequentialStart)
        print("BENCH one at a time: \(fileCount) files in \(ms(sequential)) ms (\(ms(sequential / Double(fileCount))) ms each)")

        // The path the selection bar takes now.
        var batched = oneAtATime
        for index in batched.indices {
            batched[index].isFavorite = false
            batched[index].updatedAt = .now
        }
        let batchStart = Date()
        let failures = try await repository.save(files: batched)
        let batch = Date().timeIntervalSince(batchStart)
        print("BENCH in one write: \(fileCount) files in \(ms(batch)) ms (\(ms(batch / Double(fileCount))) ms each), \(failures.count) refused")
        files = batched

        // Taken away again, by record. `permanentlyDelete` is for what the reader has already
        // thrown away — it refuses an item that was never in the Trash — and these were never the
        // reader's to throw away.
        let cleanupStart = Date()
        try await deleteBenchmarkRecords(files.map(\.id) + [folder.id])
        print("BENCH cleaned up in \(ms(Date().timeIntervalSince(cleanupStart))) ms")

        let snapshot = try await repository.fetchSnapshot()
        XCTAssertFalse(
            snapshot.folders.contains { $0.id == folder.id },
            "The benchmark's own folder is still in the archive"
        )
        XCTAssertTrue(
            snapshot.files.filter { files.map(\.id).contains($0.id) }.isEmpty,
            "The benchmark's own files are still in the archive"
        )
        #endif
    }

    /// The claim the design rests on: the cost stops following the number of items. Five times the
    /// files, and the write should take about the same time — two round trips either way.
    func testAHundredFilesCostAboutWhatTwentyDid() async throws {
        #if !ARCHIVELEAF_BULK_BENCHMARK
        throw XCTSkip("Bulk write benchmark is opt-in: pass -D ARCHIVELEAF_BULK_BENCHMARK.")
        #else
        let repository = CloudKitArchiveRepository()
        let count = 100
        let folder = ArchiveFolder(name: "Benchmark \(UUID().uuidString.prefix(8))")
        try await repository.save(folder: folder)

        var files = (0..<count).map { index -> ArchiveFile in
            let hash = String(repeating: String(format: "%02x", index % 256), count: 32)
            return ArchiveFile(
                originalFileName: "benchmark-\(index).txt",
                parentFolderID: folder.id,
                detectedFormat: .plainText,
                sourceEncoding: "utf-8",
                fileSize: 0,
                contentHash: hash + String(UUID().uuidString.prefix(0))
            )
        }
        let creationStart = Date()
        _ = try await repository.save(files: files)
        print("BENCH100 created \(count) files in \(ms(Date().timeIntervalSince(creationStart))) ms")

        for index in files.indices {
            files[index].isFavorite = true
            files[index].updatedAt = .now
        }
        let start = Date()
        let failures = try await repository.save(files: files)
        let elapsed = Date().timeIntervalSince(start)
        print("BENCH100 favorited \(count) files in \(ms(elapsed)) ms (\(ms(elapsed / Double(count))) ms each), \(failures.count) refused")

        try await deleteBenchmarkRecords(files.map(\.id) + [folder.id])
        let snapshot = try await repository.fetchSnapshot()
        XCTAssertTrue(snapshot.files.allSatisfy { !$0.originalFileName.hasPrefix("benchmark-") })
        XCTAssertTrue(snapshot.folders.allSatisfy { !$0.name.hasPrefix("Benchmark ") })
        print("BENCH100 archive back to \(snapshot.files.count) files, \(snapshot.folders.count) folders")
        #endif
    }

    private func deleteBenchmarkRecords(_ ids: [UUID]) async throws {
        let database = CKContainer(identifier: CloudKitSchema.containerIdentifier).privateCloudDatabase
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        for start in stride(from: 0, to: recordIDs.count, by: 200) {
            let end = min(start + 200, recordIDs.count)
            let (_, deletions) = try await database.modifyRecords(
                saving: [],
                deleting: Array(recordIDs[start..<end]),
                savePolicy: .changedKeys,
                atomically: false
            )
            for result in deletions.values { _ = try result.get() }
        }
    }

    private func ms(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }
}
