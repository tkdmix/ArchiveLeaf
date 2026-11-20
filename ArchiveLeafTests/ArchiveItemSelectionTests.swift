import XCTest
@testable import ArchiveLeaf

final class ArchiveItemSelectionTests: XCTestCase {
    func testEmptySelectionIsValidButHasNoCapabilities() {
        let selection = ArchiveItemSelection(items: [], requestedIDs: [])

        XCTAssertTrue(selection.isEmpty)
        XCTAssertTrue(selection.isValid)
        XCTAssertEqual(selection.count, 0)
        XCTAssertEqual(selection.items, [])
        XCTAssertEqual(selection.ids, [])
        XCTAssertEqual(selection.folders, [])
        XCTAssertEqual(selection.files, [])
        XCTAssertFalse(selection.isAllFiles)
        assertNoCapabilities(selection)
    }

    func testSingleFileHasEveryCapabilityAndPreservesInput() {
        let file = makeFile(named: "One.md")
        let selection = ArchiveItemSelection(items: [.file(file)], requestedIDs: [file.id])

        XCTAssertTrue(selection.isValid)
        XCTAssertTrue(selection.isSingle)
        XCTAssertTrue(selection.isAllFiles)
        XCTAssertEqual(selection.count, 1)
        XCTAssertEqual(selection.ids, [file.id])
        XCTAssertEqual(selection.files, [file])
        XCTAssertEqual(selection.folders, [])
        assertEveryCapability(selection)
    }

    func testMultipleFilesHaveFileAndWholeSelectionCapabilitiesExceptRename() {
        let first = makeFile(named: "First.md")
        let second = makeFile(named: "Second.md")
        let selection = ArchiveItemSelection(
            items: [.file(second), .file(first)],
            requestedIDs: [first.id, second.id]
        )

        XCTAssertEqual(selection.ids, [second.id, first.id])
        XCTAssertEqual(selection.files, [second, first])
        XCTAssertTrue(selection.isAllFiles)
        XCTAssertFalse(selection.isSingle)
        XCTAssertTrue(selection.canMove)
        XCTAssertTrue(selection.canTrash)
        XCTAssertTrue(selection.canDropIntoFolder)
        XCTAssertTrue(selection.canTag)
        XCTAssertTrue(selection.canFavorite)
        XCTAssertTrue(selection.canShare)
        XCTAssertFalse(selection.canRename)
    }

    func testFoldersHaveOnlyWholeSelectionCapabilities() {
        let first = makeFolder(named: "First")
        let second = makeFolder(named: "Second")
        let selection = ArchiveItemSelection(
            items: [.folder(first), .folder(second)],
            requestedIDs: [first.id, second.id]
        )

        XCTAssertEqual(selection.folders, [first, second])
        XCTAssertEqual(selection.files, [])
        XCTAssertFalse(selection.isAllFiles)
        XCTAssertTrue(selection.canMove)
        XCTAssertTrue(selection.canTrash)
        XCTAssertTrue(selection.canDropIntoFolder)
        XCTAssertFalse(selection.canTag)
        XCTAssertFalse(selection.canFavorite)
        XCTAssertFalse(selection.canShare)
        XCTAssertFalse(selection.canRename)
    }

    func testSingleFolderCanRename() {
        let folder = makeFolder(named: "Folder")
        let selection = ArchiveItemSelection(items: [.folder(folder)], requestedIDs: [folder.id])

        XCTAssertTrue(selection.isSingle)
        XCTAssertTrue(selection.canRename)
        XCTAssertFalse(selection.canTag)
        XCTAssertFalse(selection.canFavorite)
        XCTAssertFalse(selection.canShare)
    }

    func testMixedSelectionSupportsOnlyWholeSelectionCapabilities() {
        let folder = makeFolder(named: "Folder")
        let file = makeFile(named: "File.md")
        let selection = ArchiveItemSelection(
            items: [.folder(folder), .file(file)],
            requestedIDs: [folder.id, file.id]
        )

        XCTAssertEqual(selection.folders, [folder])
        XCTAssertEqual(selection.files, [file])
        XCTAssertTrue(selection.canMove)
        XCTAssertTrue(selection.canTrash)
        XCTAssertTrue(selection.canDropIntoFolder)
        XCTAssertFalse(selection.canTag)
        XCTAssertFalse(selection.canFavorite)
        XCTAssertFalse(selection.canShare)
        XCTAssertFalse(selection.canRename)
    }

    func testUnresolvedIDInvalidatesEveryCapabilityWithoutPartialAction() {
        let file = makeFile(named: "Resolved.md")
        let unknownID = UUID()
        let selection = ArchiveItemSelection(
            items: [.file(file)],
            requestedIDs: [file.id, unknownID]
        )

        XCTAssertFalse(selection.isValid)
        XCTAssertFalse(selection.isEmpty)
        XCTAssertEqual(selection.count, 2)
        XCTAssertEqual(selection.unknownIDs, [unknownID])
        XCTAssertFalse(selection.isSingle)
        XCTAssertFalse(selection.isAllFiles)
        assertNoCapabilities(selection)
    }

    func testDuplicateResolvedIDInvalidatesEveryCapability() {
        let file = makeFile(named: "Duplicate.md")
        let selection = ArchiveItemSelection(
            items: [.file(file), .file(file)],
            requestedIDs: [file.id]
        )

        XCTAssertFalse(selection.isValid)
        assertNoCapabilities(selection)
    }

    /// The Trash is a separate place with separate verbs. What is in it takes restoring and
    /// permanent deletion; what is in the archive takes everything else. Neither list ever shows
    /// both, so a selection holding one of each can do nothing at all rather than half of it.
    func testDiscardedItemsTakeTheTrashsVerbsAndNoneOfTheArchives() {
        let file = makeFile(named: "gone.md", isTrashed: true)
        let folder = makeFolder(named: "Gone", isTrashed: true)
        let selection = ArchiveItemSelection(
            items: [.folder(folder), .file(file)],
            requestedIDs: [folder.id, file.id]
        )

        XCTAssertTrue(selection.canRestore)
        XCTAssertTrue(selection.canDeletePermanently)
        assertNoCapabilities(selection)
    }

    func testItemsInTheArchiveTakeNoneOfTheTrashsVerbs() {
        let file = makeFile(named: "here.md")
        let selection = ArchiveItemSelection(items: [.file(file)], requestedIDs: [file.id])

        XCTAssertFalse(selection.canRestore)
        XCTAssertFalse(selection.canDeletePermanently)
        assertEveryCapability(selection)
    }

    func testAMixOfDiscardedAndKeptItemsCanDoNothing() {
        let kept = makeFile(named: "here.md")
        let discarded = makeFile(named: "gone.md", isTrashed: true)
        let selection = ArchiveItemSelection(
            items: [.file(kept), .file(discarded)],
            requestedIDs: [kept.id, discarded.id]
        )

        XCTAssertFalse(selection.canRestore)
        XCTAssertFalse(selection.canDeletePermanently)
        assertNoCapabilities(selection)
    }

    private func makeFile(named name: String, isTrashed: Bool = false) -> ArchiveFile {
        ArchiveFile(originalFileName: name, isTrashed: isTrashed, detectedFormat: .markdown)
    }

    private func makeFolder(named name: String, isTrashed: Bool = false) -> ArchiveFolder {
        ArchiveFolder(name: name, isTrashed: isTrashed)
    }

    private func assertEveryCapability(
        _ selection: ArchiveItemSelection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(selection.canMove, file: file, line: line)
        XCTAssertTrue(selection.canTrash, file: file, line: line)
        XCTAssertTrue(selection.canDropIntoFolder, file: file, line: line)
        XCTAssertTrue(selection.canTag, file: file, line: line)
        XCTAssertTrue(selection.canFavorite, file: file, line: line)
        XCTAssertTrue(selection.canShare, file: file, line: line)
        XCTAssertTrue(selection.canRename, file: file, line: line)
    }

    private func assertNoCapabilities(
        _ selection: ArchiveItemSelection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(selection.canMove, file: file, line: line)
        XCTAssertFalse(selection.canTrash, file: file, line: line)
        XCTAssertFalse(selection.canDropIntoFolder, file: file, line: line)
        XCTAssertFalse(selection.canTag, file: file, line: line)
        XCTAssertFalse(selection.canFavorite, file: file, line: line)
        XCTAssertFalse(selection.canShare, file: file, line: line)
        XCTAssertFalse(selection.canRename, file: file, line: line)
    }
}
