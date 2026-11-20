import Foundation
import XCTest
@testable import ArchiveLeaf

/// What the lists ask the archive, asked of the index instead.
///
/// These are the answers the screens used to work out by walking every file for every row. Fixing
/// them here is what lets the walk be replaced without the walk's behaviour changing.
final class ArchiveIndexTests: XCTestCase {
    private let documents = ArchiveFolder(name: "Documents")
    private let images = ArchiveFolder(name: "Images")

    func testFilesAreFoundByTheFolderTheySitIn() {
        let inside = makeFile(named: "a.md", in: documents.id)
        let alsoInside = makeFile(named: "b.md", in: documents.id)
        let elsewhere = makeFile(named: "c.png", in: images.id)
        let loose = makeFile(named: "d.txt", in: nil)
        let index = ArchiveIndex(
            files: [inside, alsoInside, elsewhere, loose],
            folders: [documents, images]
        )

        XCTAssertEqual(Set(index.files(inFolderWithID: documents.id).map(\.id)), [inside.id, alsoInside.id])
        XCTAssertEqual(index.files(inFolderWithID: images.id).map(\.id), [elsewhere.id])
        // The archive's own root is a real place, not an absence: it is what Unsorted shows.
        XCTAssertEqual(index.files(inFolderWithID: nil).map(\.id), [loose.id])
    }

    /// The number beside a row is the number of rows that row opens onto — and at the top of the
    /// tree, where the folders are not inside Unsorted, only the files count.
    func testTheCountBesideARowCountsWhatOpeningItShows() {
        let nested = ArchiveFolder(name: "Drafts", parentFolderID: documents.id)
        let index = ArchiveIndex(
            files: [makeFile(named: "a.md", in: documents.id), makeFile(named: "loose.txt", in: nil)],
            folders: [documents, nested]
        )

        XCTAssertEqual(index.itemCount(inFolderWithID: documents.id), 2)
        XCTAssertEqual(index.itemCount(inFolderWithID: nested.id), 0)
        XCTAssertEqual(index.itemCount(inFolderWithID: nil), 1)
    }

    func testEveryFileCarryingAnyOfTheseTagsAppearsOnce() {
        let work = UUID()
        let reading = UUID()
        var both = makeFile(named: "both.md", in: nil)
        both.tagIDs = [work, reading]
        var onlyWork = makeFile(named: "work.md", in: nil)
        onlyWork.tagIDs = [work]
        let untagged = makeFile(named: "plain.md", in: nil)
        let index = ArchiveIndex(files: [both, onlyWork, untagged], folders: [])

        let gathered = index.files(carryingAnyOf: [work, reading])
        XCTAssertEqual(gathered.count, 2, "A file carrying two of them is still one file")
        XCTAssertEqual(Set(gathered.map(\.id)), [both.id, onlyWork.id])
        XCTAssertEqual(Set(index.tagged.map(\.id)), [both.id, onlyWork.id])
    }

    func testFavoritesAreKeptApartFromTheRest() {
        var starred = makeFile(named: "starred.md", in: nil)
        starred.isFavorite = true
        let index = ArchiveIndex(files: [starred, makeFile(named: "plain.md", in: nil)], folders: [])

        XCTAssertEqual(index.favorites.map(\.id), [starred.id])
    }

    func testLookingUpOneThingFindsTheThing() {
        let file = makeFile(named: "a.md", in: documents.id)
        let index = ArchiveIndex(files: [file], folders: [documents])

        XCTAssertEqual(index.filesByID[file.id]?.id, file.id)
        XCTAssertEqual(index.foldersByID[documents.id]?.name, "Documents")
        XCTAssertNil(index.filesByID[UUID()])
    }

    private func makeFile(named name: String, in parentFolderID: UUID?) -> ArchiveFile {
        ArchiveFile(
            originalFileName: name,
            parentFolderID: parentFolderID,
            detectedFormat: .plainText
        )
    }
}
