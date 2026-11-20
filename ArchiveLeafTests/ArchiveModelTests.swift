import XCTest
@testable import ArchiveLeaf

final class ArchiveModelTests: XCTestCase {
    func testBookmarkNameDoesNotExposeItsStorageExtension() {
        let bookmark = ArchiveFile(
            originalFileName: "ArchiveLeaf Reference.webloc",
            detectedFormat: .bookmark
        )

        XCTAssertEqual(bookmark.sidebarDisplayName, "ArchiveLeaf Reference")
    }

    func testDocumentSearchSupportFollowsThePresentationFormat() {
        XCTAssertTrue(ImportedFormat.plainText.supportsDocumentSearch)
        XCTAssertTrue(ImportedFormat.markdown.supportsDocumentSearch)
        XCTAssertTrue(ImportedFormat.json.supportsDocumentSearch)
        XCTAssertTrue(ImportedFormat.csv.supportsDocumentSearch)
        XCTAssertFalse(ImportedFormat.jpeg.supportsDocumentSearch)
        XCTAssertFalse(ImportedFormat.png.supportsDocumentSearch)
        XCTAssertFalse(ImportedFormat.bookmark.supportsDocumentSearch)
    }

    func testFileDerivesDisplayNameAndExtension() {
        let file = ArchiveFile(
            originalFileName: "item.md",
            detectedFormat: .markdown
        )

        XCTAssertEqual(file.displayName, "item")
        XCTAssertEqual(file.sidebarDisplayName, "item.md")
        XCTAssertEqual(file.originalExtension, "md")
        XCTAssertFalse(file.isFavorite)
        XCTAssertFalse(file.isTrashed)
    }

    func testDisplayFormatOverrideDoesNotChangeDetectedFormat() {
        var file = ArchiveFile(originalFileName: "item.txt", detectedFormat: .plainText)

        file.displayFormatOverride = .markdown

        XCTAssertEqual(file.detectedFormat, .plainText)
        XCTAssertEqual(file.effectiveDisplayFormat, .markdown)
    }

    func testArchiveNamesAreComparedTrimmedAndNormalized() {
        XCTAssertEqual(
            ArchiveRules.normalizedName("  RÉSUMÉ  "),
            ArchiveRules.normalizedName("re\u{301}sume\u{301}")
        )
    }
}
