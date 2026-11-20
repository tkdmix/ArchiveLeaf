import Foundation
import XCTest
@testable import ArchiveLeaf

final class DiskArchiveCacheTests: XCTestCase {
    func testStoresReadsAndClearsCachedData() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskArchiveCache(
            directoryURL: directory,
            policy: CachePolicy(maximumSize: 100)
        )

        try await cache.store(Data("leaf".utf8), for: "file")

        let storedData = try await cache.cachedData(for: "file")
        let storedSize = try await cache.currentSize()
        XCTAssertEqual(storedData, Data("leaf".utf8))
        XCTAssertEqual(storedSize, 4)

        try await cache.removeAll()
        let clearedData = try await cache.cachedData(for: "file")
        let clearedSize = try await cache.currentSize()
        XCTAssertNil(clearedData)
        XCTAssertEqual(clearedSize, 0)
    }

    func testEvictsLeastRecentlyUsedEntryAtCapacity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskArchiveCache(
            directoryURL: directory,
            policy: CachePolicy(maximumSize: 8)
        )

        try await cache.store(Data("aaaa".utf8), for: "a")
        try await Task.sleep(for: .milliseconds(20))
        try await cache.store(Data("bbbb".utf8), for: "b")
        try await Task.sleep(for: .milliseconds(20))
        _ = try await cache.cachedData(for: "a")
        try await Task.sleep(for: .milliseconds(20))
        try await cache.store(Data("cccc".utf8), for: "c")

        let dataA = try await cache.cachedData(for: "a")
        let dataB = try await cache.cachedData(for: "b")
        let dataC = try await cache.cachedData(for: "c")
        let size = try await cache.currentSize()
        XCTAssertNotNil(dataA)
        XCTAssertNil(dataB)
        XCTAssertNotNil(dataC)
        XCTAssertEqual(size, 8)
    }

    func testDoesNotStoreEntryLargerThanTotalCapacity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskArchiveCache(
            directoryURL: directory,
            policy: CachePolicy(maximumSize: 3)
        )

        try await cache.store(Data("leaf".utf8), for: "large")

        let data = try await cache.cachedData(for: "large")
        let size = try await cache.currentSize()
        XCTAssertNil(data)
        XCTAssertEqual(size, 0)
    }

    func testIncludesAndClearsOnlyEligibleLegacyTemporaryFiles() async throws {
        let directory = temporaryDirectory()
        let temporaryDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let cutoff = Date(timeIntervalSinceReferenceDate: 1_000)
        let eligible = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        let recent = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let unknownExtension = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        let nonUUID = temporaryDirectory.appendingPathComponent("not-an-id.png")
        let hidden = temporaryDirectory.appendingPathComponent(".\(UUID().uuidString).png")
        let nestedDirectory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedFile = nestedDirectory.appendingPathComponent("kept.txt")
        let symbolicLink = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
        try Data("old".utf8).write(to: eligible)
        try Data("new".utf8).write(to: recent)
        try Data("unknown".utf8).write(to: unknownExtension)
        try Data("nonUUID".utf8).write(to: nonUUID)
        try Data("hidden".utf8).write(to: hidden)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nestedFile)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: eligible)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(-1)], ofItemAtPath: eligible.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(1)], ofItemAtPath: recent.path)

        let diskCache = DiskArchiveCache(directoryURL: directory, policy: CachePolicy(maximumSize: 100))
        let cache = ArchiveCacheWithLegacyTemporaryCleanup(
            cache: diskCache,
            temporaryDirectoryURL: temporaryDirectory,
            cutoff: cutoff
        )
        try await cache.store(Data("disk".utf8), for: "key")

        let combinedSize = try await cache.currentSize()
        XCTAssertEqual(combinedSize, 7)
        try await cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: eligible.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownExtension.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonUUID.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hidden.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symbolicLink.path))
    }

    func testIncludesAndClearsOnlyEligibleLegacyCoverageDirectories() async throws {
        let directory = temporaryDirectory()
        let containerDataDirectory = temporaryDirectory()
        let temporaryDirectory = containerDataDirectory.appendingPathComponent("tmp", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: containerDataDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let cutoff = Date(timeIntervalSinceReferenceDate: 1_000)
        let empty = coverageDirectory(in: containerDataDirectory)
        let profile = coverageDirectory(in: containerDataDirectory)
        let profileData = profile.appendingPathComponent("coverage.profraw")
        let recent = coverageDirectory(in: containerDataDirectory)
        let nested = coverageDirectory(in: containerDataDirectory)
        let unexpectedFile = coverageDirectory(in: containerDataDirectory)
        let symlink = coverageDirectory(in: containerDataDirectory)
        let nonCandidate = containerDataDirectory.appendingPathComponent("not-coverage", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("profile".utf8).write(to: profileData)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent("nested", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unexpectedFile, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unexpectedFile.appendingPathComponent("details.txt"))
        try FileManager.default.createDirectory(at: nonCandidate, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: nonCandidate)
        for directory in [empty, profile, nested, unexpectedFile] {
            try FileManager.default.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-1)],
                ofItemAtPath: directory.path
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(1)],
            ofItemAtPath: recent.path
        )

        let diskCache = DiskArchiveCache(directoryURL: directory, policy: CachePolicy(maximumSize: 100))
        let cache = ArchiveCacheWithLegacyTemporaryCleanup(
            cache: diskCache,
            temporaryDirectoryURL: temporaryDirectory,
            containerDataDirectoryURL: containerDataDirectory,
            cutoff: cutoff
        )
        try await cache.store(Data("disk".utf8), for: "key")
        let emptySize = try fileSize(of: empty)
        let profileDirectorySize = try fileSize(of: profile)

        let combinedSize = try await cache.currentSize()
        XCTAssertEqual(combinedSize, 4 + emptySize + profileDirectorySize + 7)
        try await cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unexpectedFile.path))
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonCandidate.path))
    }

    func testIncludesAndClearsOnlyEligibleLegacyTemporaryDirectories() async throws {
        let directory = temporaryDirectory()
        let temporaryDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let cutoff = Date(timeIntervalSinceReferenceDate: 1_000)
        let preview = temporaryDirectory.appendingPathComponent("ArchiveLeafPreview", isDirectory: true)
        let backup = temporaryDirectory.appendingPathComponent("ArchiveLeafBackup-\(UUID().uuidString)", isDirectory: true)
        let bookmarkImport = temporaryDirectory.appendingPathComponent("ArchiveLeaf-BookmarkImport-\(UUID().uuidString)", isDirectory: true)
        let recent = temporaryDirectory.appendingPathComponent("ArchiveLeafBackup-\(UUID().uuidString)", isDirectory: true)
        let unknown = temporaryDirectory.appendingPathComponent("ArchiveLeafBackup-not-a-uuid", isDirectory: true)
        let symbolicLink = temporaryDirectory.appendingPathComponent("ArchiveLeaf-BookmarkImport-\(UUID().uuidString)", isDirectory: true)
        let preservedTarget = temporaryDirectory.appendingPathComponent("preserved", isDirectory: true)
        let linkedFile = preview.appendingPathComponent("outside-link")
        try FileManager.default.createDirectory(at: preview.appendingPathComponent("items"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bookmarkImport.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preservedTarget, withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: preview.appendingPathComponent("items/image.jpg"))
        try Data("backup".utf8).write(to: backup.appendingPathComponent("archive"))
        try Data("bookmarks".utf8).write(to: bookmarkImport.appendingPathComponent("nested/export.json"))
        try Data("outside".utf8).write(to: preservedTarget.appendingPathComponent("kept"))
        try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: preservedTarget)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: preservedTarget)
        for directory in [preview, backup, bookmarkImport, unknown] {
            try FileManager.default.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-1)],
                ofItemAtPath: directory.path
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(1)],
            ofItemAtPath: recent.path
        )

        let diskCache = DiskArchiveCache(directoryURL: directory, policy: CachePolicy(maximumSize: 100))
        let cache = ArchiveCacheWithLegacyTemporaryCleanup(
            cache: diskCache,
            temporaryDirectoryURL: temporaryDirectory,
            cutoff: cutoff
        )
        try await cache.store(Data("disk".utf8), for: "key")

        let combinedSize = try await cache.currentSize()
        XCTAssertEqual(combinedSize, 4 + 7 + 6 + 9)
        try await cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkImport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symbolicLink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedTarget.path))
    }

    func testIncludesAndClearsOnlyWellFormedLegacyTemporaryBackupPackages() async throws {
        let directory = temporaryDirectory()
        let temporaryDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let cutoff = Date(timeIntervalSinceReferenceDate: 1_000)
        let package = backupPackageDirectory(in: temporaryDirectory)
        let recent = backupPackageDirectory(in: temporaryDirectory)
        let malformed = backupPackageDirectory(in: temporaryDirectory)
        let symlinkedAssets = backupPackageDirectory(in: temporaryDirectory)
        let linkedAssets = temporaryDirectory.appendingPathComponent("linked-assets", isDirectory: true)
        let linkedTarget = temporaryDirectory.appendingPathComponent("linked-target", isDirectory: true)
        try makeBackupPackage(at: package)
        try makeBackupPackage(at: recent)
        try makeBackupPackage(at: malformed)
        try makeBackupPackage(at: symlinkedAssets)
        try Data("extra".utf8).write(to: malformed.appendingPathComponent("unexpected"))
        try FileManager.default.createDirectory(at: linkedAssets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedTarget, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: linkedTarget.appendingPathComponent("kept"))
        try FileManager.default.removeItem(at: symlinkedAssets.appendingPathComponent("Assets"))
        try FileManager.default.createSymbolicLink(
            at: symlinkedAssets.appendingPathComponent("Assets"),
            withDestinationURL: linkedAssets
        )
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("Assets/outside-link"),
            withDestinationURL: linkedTarget
        )
        for directory in [package, malformed, symlinkedAssets] {
            try FileManager.default.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-1)],
                ofItemAtPath: directory.path
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(1)],
            ofItemAtPath: recent.path
        )

        let diskCache = DiskArchiveCache(directoryURL: directory, policy: CachePolicy(maximumSize: 100))
        let cache = ArchiveCacheWithLegacyTemporaryCleanup(
            cache: diskCache,
            temporaryDirectoryURL: temporaryDirectory,
            cutoff: cutoff
        )
        try await cache.store(Data("disk".utf8), for: "key")

        let combinedSize = try await cache.currentSize()
        XCTAssertEqual(combinedSize, 4 + 8)
        try await cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkedAssets.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedTarget.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeafCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func coverageDirectory(in parent: URL) -> URL {
        parent.appendingPathComponent("\(UUID().uuidString)-123-abcdef", isDirectory: true)
    }

    private func backupPackageDirectory(in parent: URL) -> URL {
        parent.appendingPathComponent("ArchiveLeaf-\(UUID().uuidString).archiveleafbackup", isDirectory: true)
    }

    private func makeBackupPackage(at url: URL) throws {
        let assets = url.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url.appendingPathComponent("manifest.json"))
        try Data("assets".utf8).write(to: assets.appendingPathComponent("content"))
    }

    private func fileSize(of url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
}
