#if os(macOS)
import XCTest
@testable import ArchiveLeaf

final class ArchiveSourceOutlineDropTests: XCTestCase {
    func testMetadataDropAcceptsOnlyResolvedFiles() {
        let first = ArchiveFile(originalFileName: "First.md", detectedFormat: .markdown)
        let second = ArchiveFile(originalFileName: "Second.md", detectedFormat: .markdown)

        XCTAssertEqual(
            archiveMetadataDropFileIDs(
                requestedIDs: [first.id, second.id],
                resolvedItems: [.file(first), .file(second)]
            ),
            [first.id, second.id]
        )
    }

    func testMetadataDropRejectsMixedFolderAndFileSelection() {
        let folder = ArchiveFolder(name: "Folder")
        let file = ArchiveFile(originalFileName: "File.md", detectedFormat: .markdown)

        XCTAssertNil(archiveMetadataDropFileIDs(
            requestedIDs: [folder.id, file.id],
            resolvedItems: [.folder(folder), .file(file)]
        ))
    }

    func testMetadataDropRejectsFolderOnlySelection() {
        let folder = ArchiveFolder(name: "Folder")

        XCTAssertNil(archiveMetadataDropFileIDs(
            requestedIDs: [folder.id],
            resolvedItems: [.folder(folder)]
        ))
    }

    func testMetadataDropRejectsUnknownIDWithoutPartialResult() {
        let file = ArchiveFile(originalFileName: "File.md", detectedFormat: .markdown)

        XCTAssertNil(archiveMetadataDropFileIDs(
            requestedIDs: [file.id, UUID()],
            resolvedItems: [.file(file)]
        ))
    }

    func testMetadataDropRejectsDuplicateRequestedID() {
        let file = ArchiveFile(originalFileName: "File.md", detectedFormat: .markdown)

        XCTAssertNil(archiveMetadataDropFileIDs(
            requestedIDs: [file.id, file.id],
            resolvedItems: [.file(file), .file(file)]
        ))
    }
}
#endif
