import UIKit
import XCTest

/// The wide iPad reader is a browser and a viewer at the same time. Its width is decided from the
/// live container, so this test explicitly rotates an iPad before launch instead of inheriting the
/// orientation left by another UI test.
///
/// A phone never reaches the two-pane threshold, so on a phone these are skipped rather than failed.
/// Run on an iPhone they reported "The iPad reader panes did not appear" — which is true, and is the
/// designed behaviour, and a suite that goes red for working correctly is a suite people stop
/// reading. The skip is decided from the device, not from whether the panes turned up: on an iPad
/// their absence is still a failure.
final class ArchiveTabletTwoPaneUITests: XCTestCase {
    @MainActor
    func testTrashPreviewHidesFavoriteAndShareButKeepsInfo() throws {
        try skipUnlessTablet()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchArchive(environment: ["ARCHIVELEAF_UI_TEST_TRASH": "1"])
        defer { app.terminate() }

        let browser = tabletPane("archiveTabletBrowserPane", in: app)
        let viewer = tabletPane("archiveTabletViewerPane", in: app)
        guard browser.waitForExistence(timeout: 5), viewer.waitForExistence(timeout: 5) else {
            XCTFail("The iPad reader panes did not appear")
            return
        }

        openTrash(in: app)

        let trashedFile = browser.descendants(matching: .any)
            .matching(identifier: "item-row-Welcome.md")
            .firstMatch
        guard trashedFile.waitForExistence(timeout: 5), trashedFile.isHittable else {
            XCTFail("Welcome.md was not visible in the Trash browser pane")
            return
        }
        trashedFile.tap()

        let documentHeading = viewer.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Welcome to ArchiveLeaf")
        ).firstMatch
        guard documentHeading.waitForExistence(timeout: 5) else {
            XCTFail("The trashed document did not appear in the viewer pane")
            return
        }

        XCTAssertFalse(viewer.buttons["Add to Favorites"].exists)
        XCTAssertFalse(viewer.buttons["Remove from Favorites"].exists)
        XCTAssertFalse(viewer.buttons["Share"].exists)
        XCTAssertFalse(viewer.buttons["Share…"].exists)
        XCTAssertTrue(viewer.buttons["Info"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLandscapeKeepsTheBrowserBesideTheViewerAndCanMaximizeIt() throws {
        try skipUnlessTablet()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchArchive()
        defer { app.terminate() }

        let browser = tabletPane("archiveTabletBrowserPane", in: app)
        let viewer = tabletPane("archiveTabletViewerPane", in: app)
        guard browser.waitForExistence(timeout: 5) else {
            XCTFail("The landscape browser pane did not appear")
            return
        }
        guard viewer.waitForExistence(timeout: 5) else {
            XCTFail("The landscape viewer pane did not appear")
            return
        }

        let documents = browser.descendants(matching: .any)
            .matching(identifier: "folder-row-Documents")
            .firstMatch
        if !documents.waitForExistence(timeout: 2) {
            let namedBack = browser.buttons["BackButton"].firstMatch
            let back = namedBack.exists
                ? namedBack
                : browser.navigationBars.firstMatch.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 3), back.isHittable else {
                XCTFail("The browser could not return to the folder tree")
                return
            }
            back.tap()
        }

        guard documents.waitForExistence(timeout: 5), documents.isHittable else {
            XCTFail("Documents was not visible in the browser pane")
            return
        }
        documents.tap()

        let semanticWelcome = browser.buttons
            .matching(NSPredicate(format: "identifier CONTAINS %@", "item-row-Welcome.md"))
            .firstMatch
        guard semanticWelcome.waitForExistence(timeout: 5), semanticWelcome.isHittable else {
            XCTFail("Welcome.md was not visible in the browser pane")
            return
        }
        semanticWelcome.tap()

        // The document and its list remain visible as two projections of the same browsing state.
        let documentHeading = viewer.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Welcome to ArchiveLeaf")
        ).firstMatch
        guard documentHeading.waitForExistence(timeout: 5) else {
            XCTFail("Welcome.md did not appear in the viewer pane")
            return
        }
        guard browser.exists,
              browser.descendants(matching: .any)
                .matching(identifier: "item-row-Welcome.md")
                .firstMatch
                .exists else {
            XCTFail("The browser did not remain beside the viewer")
            return
        }

        // A reader selection is idempotent: selecting the already-previewed file must not put a
        // second copy of its detail screen on the browser stack.
        semanticWelcome.tap()
        XCTAssertFalse(
            browser.buttons["Documents"].waitForExistence(timeout: 2),
            "Selecting a previewed file added a detail-level back button to the browser"
        )
        XCTAssertTrue(
            browser.descendants(matching: .any)
                .matching(identifier: "item-row-Welcome.md")
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let visibility = app.buttons["archiveTabletViewerVisibility"]
        guard visibility.waitForExistence(timeout: 3), visibility.isHittable else {
            XCTFail("The viewer visibility control did not appear")
            return
        }
        visibility.tap()

        guard viewer.waitForExistence(timeout: 3) else {
            XCTFail("The viewer disappeared while maximizing")
            return
        }
        guard !browser.waitForExistence(timeout: 2) else {
            XCTFail("The browser remained visible while the viewer was maximized")
            return
        }
        XCTAssertEqual(visibility.label, "Show Browser")

        visibility.tap()
        guard browser.waitForExistence(timeout: 3) else {
            XCTFail("The browser did not return after restoring it")
            return
        }
        XCTAssertTrue(
            browser.descendants(matching: .any)
                .matching(identifier: "item-row-Welcome.md")
                .firstMatch
                .waitForExistence(timeout: 3)
        )
    }

    /// Asked of the runner's own device, which is the thing that decides whether two panes are
    /// possible at all — not of the app, whose answer would be the very thing under test.
    @MainActor
    private func skipUnlessTablet() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The two-pane reader exists on iPad only"
        )
    }
}
