import CloudKit
import Foundation
import XCTest
@testable import ArchiveLeaf

/// One-shot: takes away what a failed benchmark run left behind, and nothing else.
final class BenchmarkLeftoverCleanup: XCTestCase {
    func testRemovesBenchmarkRecords() async throws {
        #if !ARCHIVELEAF_BULK_BENCHMARK
        throw XCTSkip("Cleanup is opt-in: pass -D ARCHIVELEAF_BULK_BENCHMARK.")
        #else
        let repository = CloudKitArchiveRepository()
        let snapshot = try await repository.fetchSnapshot()
        let files = snapshot.files.filter { $0.originalFileName.hasPrefix("benchmark-") }
        let folders = snapshot.folders.filter { $0.name.hasPrefix("Benchmark ") }
        print("CLEANUP found \(files.count) files and \(folders.count) folders left behind")
        guard !files.isEmpty || !folders.isEmpty else { return }

        let database = CKContainer(identifier: CloudKitSchema.containerIdentifier).privateCloudDatabase
        let recordIDs = (files.map(\.id) + folders.map(\.id)).map { CKRecord.ID(recordName: $0.uuidString) }
        let (_, deletions) = try await database.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .changedKeys,
            atomically: false
        )
        for result in deletions.values { _ = try result.get() }

        let after = try await repository.fetchSnapshot()
        print("CLEANUP archive now holds \(after.files.count) files, \(after.folders.count) folders")
        XCTAssertTrue(after.files.allSatisfy { !$0.originalFileName.hasPrefix("benchmark-") })
        XCTAssertTrue(after.folders.allSatisfy { !$0.name.hasPrefix("Benchmark ") })
        #endif
    }
}
