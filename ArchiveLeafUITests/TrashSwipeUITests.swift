import XCTest

final class TrashSwipeUITests: XCTestCase {
    /// The Trash's row swipe carries one thing, on every device: Restore. A leading swipe is the
    /// iPad's own gesture for bringing the sidebar out, so both actions could not be split across
    /// the two edges, and a row whose swipes mean different things on a phone and on a pad is worse
    /// than one gesture that means the same on both. What the swipe does is therefore the
    /// restorative one, and the deletion that cannot be undone is left where it has to be reached
    /// on purpose — the context menu, behind its own question.
    @MainActor
    func testTheSwipeRestoresAndOffersNothingElse() throws {
        let app = launchArchive(environment: ["ARCHIVELEAF_UI_TEST_TRASH": "1"])
        openTrash(in: app)

        let trashedFile = trashRow(in: app)
        XCTAssertTrue(trashedFile.waitForExistence(timeout: 5))
        trashedFile.swipeLeft()

        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 2))
        // Nothing that destroys anything is one slide away.
        XCTAssertFalse(app.buttons["Delete Permanently"].exists)
        restore.tap()
        XCTAssertFalse(trashedFile.waitForExistence(timeout: 2))

        app.terminate()
        let relaunched = launchArchive(environment: ["ARCHIVELEAF_UI_TEST_TRASH": "1"])
        openTrash(in: relaunched)

        let filePendingDeletion = trashRow(in: relaunched)
        XCTAssertTrue(filePendingDeletion.waitForExistence(timeout: 5))
        filePendingDeletion.press(forDuration: 1.0)

        let delete = relaunched.buttons["Delete Permanently"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()

        // Asked before anything is destroyed, and the question says what a folder takes with it.
        XCTAssertTrue(
            relaunched.staticTexts["Permanently Delete This Item?"].waitForExistence(timeout: 2)
        )
        let warningMessage = relaunched.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "A folder deletion also removes everything inside it."
            )
        ).firstMatch
        XCTAssertTrue(warningMessage.exists)
        relaunched.terminate()
    }

    @MainActor
    private func trashRow(in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.staticText, identifier: "Welcome.md").firstMatch
    }
}
