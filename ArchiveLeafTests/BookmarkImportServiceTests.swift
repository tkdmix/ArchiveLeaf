import Foundation
import XCTest
@testable import ArchiveLeaf

final class BookmarkImportParsingTests: XCTestCase {
    func testReadsRaindropColumnsByHeading() throws {
        let csv = """
        id,title,note,excerpt,url,folder,tags,created,cover,highlights,favorite
        1,"MarkEdit, reviewed",a note,,https://example.com/a,sync,"macOS, ツール",2026-04-11T02:14:34.000Z,https://example.com/cover.png,,true
        """
        let parsed = try RaindropCSVParser().bookmarks(from: Data(csv.utf8))

        XCTAssertEqual(parsed.unreadableCount, 0)
        let bookmark = try XCTUnwrap(parsed.bookmarks.first)
        XCTAssertEqual(bookmark.title, "MarkEdit, reviewed")
        XCTAssertEqual(bookmark.url.absoluteString, "https://example.com/a")
        XCTAssertEqual(bookmark.folderPathComponents, ["sync"])
        XCTAssertEqual(bookmark.tagNames, ["macOS", "ツール"])
        XCTAssertTrue(bookmark.isFavorite)
        XCTAssertEqual(bookmark.addedAt, ISO8601DateFormatter().date(from: "2026-04-11T02:14:34Z"))
    }

    /// A nested Raindrop collection, whichever way that release writes it. A flat name is one step,
    /// so the same split serves both and neither needs its own path through the parser.
    func testSplitsANestedRaindropCollectionIntoSteps() throws {
        let csv = """
        title,url,folder,tags,created,favorite
        Nested,https://example.com/n,Parent/Child,,,false
        Flat,https://example.com/f,sync,,,false
        """
        let parsed = try RaindropCSVParser().bookmarks(from: Data(csv.utf8))

        XCTAssertEqual(parsed.bookmarks.map(\.folderPathComponents), [["Parent", "Child"], ["sync"]])
    }

    func testCountsRaindropRowsWithoutAUsableAddress() throws {
        let csv = """
        title,url,folder,tags,created,favorite
        Good,https://example.com/a,sync,,,false
        Bad,not-a-url,sync,,,false
        Local,file:///etc/hosts,sync,,,false
        """
        let parsed = try RaindropCSVParser().bookmarks(from: Data(csv.utf8))

        XCTAssertEqual(parsed.bookmarks.count, 1)
        XCTAssertEqual(parsed.unreadableCount, 2)
    }

    func testKeepsQuotedNewlinesInsideOneRaindropRow() throws {
        let csv = "title,url,folder,tags,created,favorite\r\n\"Two\nlines\",https://example.com/a,sync,,,false\r\n"
        let parsed = try RaindropCSVParser().bookmarks(from: Data(csv.utf8))

        XCTAssertEqual(parsed.bookmarks.count, 1)
        XCTAssertEqual(parsed.bookmarks.first?.title, "Two\nlines")
    }

    func testReadsGoodLinksItems() throws {
        let json = """
        [
            {
                "title": "google.com",
                "tags": ["00daily\\/0-srch", "99pw"],
                "addedAt": 1786870718.354394,
                "summary": "dropped",
                "starred": true,
                "url": "https:\\/\\/www.google.com\\/"
            }
        ]
        """
        let parsed = try GoodLinksJSONParser().bookmarks(from: Data(json.utf8))

        let bookmark = try XCTUnwrap(parsed.bookmarks.first)
        XCTAssertEqual(bookmark.title, "google.com")
        XCTAssertEqual(bookmark.tagNames, ["00daily/0-srch", "99pw"])
        XCTAssertTrue(bookmark.isFavorite)
        XCTAssertTrue(bookmark.folderPathComponents.isEmpty)
        XCTAssertEqual(bookmark.addedAt, Date(timeIntervalSince1970: 1786870718.354394))
    }

    func testRefusesAFileThatIsNotTheChosenAppsExport() {
        XCTAssertThrowsError(try GoodLinksJSONParser().bookmarks(from: Data("id,url\n1,x".utf8)))
    }

    func testPutsTheSourceInFrontOfEveryImportedTag() {
        XCTAssertEqual(BookmarkImportSource.raindrop.tagName(for: "macOS"), "Raindrop/macOS")
        XCTAssertEqual(
            BookmarkImportSource.goodLinks.tagName(for: "00daily/0-srch"),
            "GoodLinks/00daily/0-srch"
        )
        XCTAssertNil(BookmarkImportSource.raindrop.tagName(for: "   "))
    }
}

final class BookmarkImportServiceTests: XCTestCase {
    func testFilesRaindropBookmarksUnderItsOwnFolderAndTagBranch() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        First,https://example.com/a,sync,"macOS, ツール",2026-04-11T02:14:34.000Z,true
        Second,https://example.com/b,Unsorted,,,false
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.duplicateCount, 0)
        XCTAssertTrue(summary.failures.isEmpty)

        let snapshot = await repository.fetchSnapshot()
        let root = try XCTUnwrap(snapshot.folders.first { $0.parentFolderID == nil })
        XCTAssertEqual(root.name, "Raindrop")
        XCTAssertEqual(
            Set(snapshot.folders.filter { $0.parentFolderID == root.id }.map(\.name)),
            ["sync", "Unsorted"]
        )
        XCTAssertEqual(snapshot.tags.map(\.name).sorted(), ["Raindrop/macOS", "Raindrop/ツール"])

        let first = try XCTUnwrap(snapshot.files.first { $0.displayName == "First" })
        XCTAssertEqual(first.detectedFormat, .bookmark)
        XCTAssertTrue(first.isFavorite)
        XCTAssertEqual(first.tagIDs.count, 2)
        XCTAssertEqual(
            first.sourceModifiedAt,
            ISO8601DateFormatter().date(from: "2026-04-11T02:14:34Z")
        )
    }

    func testKeepsGoodLinksBookmarksFlatUnderItsOwnFolder() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("goodlinks.json")
        try Data("""
        [
            {"url": "https://example.com/a", "title": "A", "tags": ["00daily/0-srch"], "starred": false},
            {"url": "https://example.com/b", "title": "B", "tags": [], "starred": true}
        ]
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .goodLinks)

        XCTAssertEqual(summary.importedCount, 2)
        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.folders.map(\.name), ["GoodLinks"])
        let root = try XCTUnwrap(snapshot.folders.first)
        XCTAssertTrue(snapshot.files.allSatisfy { $0.parentFolderID == root.id })
        XCTAssertEqual(snapshot.tags.map(\.name), ["GoodLinks/00daily/0-srch"])
    }

    /// An imported tag stands beside a tag of the same name that was already there, rather than
    /// being folded into it. Keeping the two apart is the whole point of the source's own branch.
    func testDoesNotMergeAnImportedTagIntoAnExistingOneOfTheSameName() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        First,https://example.com/a,sync,macOS,,false
        """.utf8).write(to: exportURL)
        let existing = ArchiveTag(name: "macOS")
        let repository = InMemoryArchiveRepository(tags: [existing])

        _ = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.tags.map(\.name).sorted(), ["Raindrop/macOS", "macOS"])
        let imported = try XCTUnwrap(snapshot.files.first)
        XCTAssertFalse(imported.tagIDs.contains(existing.id))
    }

    func testSkipsBookmarksAlreadyOnTheShelfAndReusesWhatTheFirstImportMade() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        First,https://example.com/a,sync,macOS,,false
        Second,https://example.com/b,sync,,,false
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()
        let service = BookmarkImportService(repository: repository)

        _ = try await service.importBookmarks(from: exportURL, source: .raindrop)
        let second = try await service.importBookmarks(from: exportURL, source: .raindrop)

        XCTAssertEqual(second.importedCount, 0)
        XCTAssertEqual(second.duplicateCount, 2)
        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.folders.map(\.name).sorted(), ["Raindrop", "sync"])
        XCTAssertEqual(snapshot.files.count, 2)
        XCTAssertEqual(snapshot.tags.map(\.name), ["Raindrop/macOS"])
    }

    func testSkipsAPageTheExportListsTwice() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        Once,https://example.com/a,sync,,,false
        Again,https://example.com/a,Unsorted,,,false
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
    }

    /// Two bookmarks in one folder whose titles read the same. The archive refuses two rows of one
    /// name beside each other, so the second is given a free one rather than the import failing.
    func testGivesASecondBookmarkOfTheSameTitleAFreeName() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        Same,https://example.com/a,sync,,,false
        Same,https://example.com/b,sync,,,false
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        XCTAssertEqual(summary.importedCount, 2)
        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.files.map(\.displayName).sorted(), ["Same", "Same 2"])
    }

    /// A title carrying the characters a file name cannot, which is where the stored `.webloc`
    /// gets its name from.
    func testStoresATitleThatCannotBeAFileNameAsIs() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        "Swift/Xcode: notes",https://example.com/a,sync,,,false
        """.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        XCTAssertEqual(summary.importedCount, 1)
        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.files.first?.displayName, "Swift-Xcode- notes")
    }

    /// The stored asset is the standard property list, not a rewritten form of it: opening an
    /// imported bookmark has to work the same way as one that arrived any other way.
    func testStoresTheStandardBookmarkFile() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("goodlinks.json")
        try Data(#"[{"url": "https://example.com/a", "title": "A"}]"#.utf8).write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        _ = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .goodLinks)

        let snapshot = await repository.fetchSnapshot()
        let file = try XCTUnwrap(snapshot.files.first)
        let contentURL = try await repository.fileContentURL(for: file.id)
        defer { try? FileManager.default.removeItem(at: contentURL) }
        let storedURL = try BookmarkDocument.url(from: Data(contentsOf: contentURL))
        XCTAssertEqual(storedURL.absoluteString, "https://example.com/a")
        XCTAssertEqual(file.importState, .completed)
    }

    func testRefusesAnEmptyExport() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data().write(to: exportURL)
        let repository = InMemoryArchiveRepository()

        do {
            _ = try await BookmarkImportService(repository: repository)
                .importBookmarks(from: exportURL, source: .raindrop)
            XCTFail("An empty export should be refused.")
        } catch {
            let snapshot = await repository.fetchSnapshot()
            XCTAssertTrue(snapshot.folders.isEmpty)
        }
    }

    /// A whole export is one write. Counted rather than timed: in memory a write is free, so a
    /// per-bookmark save put back here would look correct while costing four round trips a bookmark
    /// against the real archive.
    func testWritesTheWholeExportInOneBatch() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let exportURL = workspace.appendingPathComponent("raindrop.csv")
        try Data("""
        title,url,folder,tags,created,favorite
        First,https://example.com/a,sync,,,false
        Second,https://example.com/b,sync,,,false
        Third,https://example.com/c,sync,,,false
        """.utf8).write(to: exportURL)
        let repository = BatchCountingRepository()

        let summary = try await BookmarkImportService(repository: repository)
            .importBookmarks(from: exportURL, source: .raindrop)

        let batches = await repository.fileWriteBatches
        let singleWrites = await repository.singleFileWrites
        XCTAssertEqual(summary.importedCount, 3)
        XCTAssertEqual(batches, [3])
        XCTAssertEqual(singleWrites, 0, "A bookmark was written on its own")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkImportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

/// An in-memory archive that records how the files arrived.
private actor BatchCountingRepository: ArchiveRepository, DuplicateFileLookingUp {
    private let backing = InMemoryArchiveRepository()
    private(set) var fileWriteBatches: [Int] = []
    private(set) var singleFileWrites = 0

    func fetchSnapshot() async throws -> ArchiveSnapshot { await backing.fetchSnapshot() }
    func fetchTrashedFiles() async throws -> [ArchiveFile] { await backing.fetchTrashedFiles() }
    func fetchTrashedFolders() async throws -> [ArchiveFolder] { await backing.fetchTrashedFolders() }
    func fileContentURL(for fileID: UUID) async throws -> URL {
        try await backing.fileContentURL(for: fileID)
    }
    func save(folder: ArchiveFolder) async throws { try await backing.save(folder: folder) }
    func save(tag: ArchiveTag) async throws { await backing.save(tag: tag) }
    func delete(tag: ArchiveTag) async throws { await backing.delete(tag: tag) }
    func files(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile] {
        await backing.files(matchingContentHashes: hashes)
    }

    func save(file: ArchiveFile) async throws {
        singleFileWrites += 1
        try await backing.save(file: file)
    }

    func save(file: ArchiveFile, assetURL: URL) async throws {
        singleFileWrites += 1
        try await backing.save(file: file, assetURL: assetURL)
    }

    func create(files: [ArchiveFileAsset]) async throws -> [UUID: any Error] {
        fileWriteBatches.append(files.count)
        return try await backing.create(files: files)
    }
}
