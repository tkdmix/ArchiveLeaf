#if os(macOS)
import XCTest

/// The Mac's browser pane, which is the only one ArchiveLeaf renders itself. On iOS the same link
/// opens `SFSafariViewController`, whose bar, errors, and retry belong to Safari and are neither
/// ArchiveLeaf's to draw nor its to assert on.
final class BrowserFailureUITests: XCTestCase {
    @MainActor
    func testFailedPageOffersRetryAndExternalBrowser() {
        let app = launchArchive(environment: ["ARCHIVELEAF_UI_TEST_BROWSER_FAILURE": "1"])
        showFolderTree(in: app)

        folderRow(named: "Documents", in: app).tap()
        let welcome = app.descendants(matching: .any)
            .matching(identifier: "item-row-Welcome.md")
            .firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 3))
        welcome.tap()

        let unavailableLink = app.links["Open unavailable test page"]
        XCTAssertTrue(unavailableLink.waitForExistence(timeout: 3))
        unavailableLink.tap()

        XCTAssertTrue(app.staticTexts["Page Couldn’t Be Loaded"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Try Again"].exists)
        XCTAssertTrue(app.buttons["Open in Browser"].exists)

        // The bar above it: four controls and the way back to the document, and no address.
        // The address was never typed here and cannot be, so showing it only spent the width.
        for control in ["Back", "Forward", "Reload", "Open in Browser", "Back to Document"] {
            XCTAssertTrue(app.buttons[control].exists, "The browser bar has no \(control)")
        }
        let address = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "127.0.0.1")
        )
        XCTAssertEqual(address.count, 0, "The address is still on screen")
        app.terminate()
    }
}
#endif
