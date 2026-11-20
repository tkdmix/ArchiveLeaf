import XCTest

final class LocalizationUITests: XCTestCase {
    /// The interface is translated; what the reader put in the archive is not. A folder called
    /// "Documents" keeps that name in Japanese, because it is the reader's word rather than ours.
    @MainActor
    func testJapaneseNavigationKeepsArchiveNamesVerbatim() {
        let app = launchArchive(language: "ja", locale: "ja_JP")

        // Ours, and translated.
        XCTAssertTrue(tab(labeled: "フォルダ", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(tab(labeled: "お気に入り", in: app).exists)
        XCTAssertTrue(tab(labeled: "タグ", in: app).exists)
        XCTAssertTrue(tab(labeled: "ゴミ箱", in: app).exists)

        showFolderTree(in: app)

        // The reader's, and left exactly as it was written.
        XCTAssertTrue(folderRow(named: "Documents", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(folderRow(named: "Images", in: app).exists)
    }
}
