import XCTest

/// Going into a folder, coming back up, and switching areas — driven the way a reader drives it.
///
/// These are addressed by accessibility identifier rather than by the words on screen. The three
/// tests that were here before this file all failed for the same reason: they spelled out labels,
/// and the labels changed. An identifier is part of the app's contract with its tests; a label is
/// wording, and wording is allowed to move.
final class BrowsingNavigationUITests: XCTestCase {
    @MainActor
    func testOpeningAFolderAndComingBackUpOneLevel() {
        let app = launchArchive()
        showFolderTree(in: app)

        let documents = folderRow(named: "Documents", in: app)
        XCTAssertTrue(documents.waitForExistence(timeout: 5))
        documents.tap()

        // The folder's own list is showing, and the tree behind it is not.
        assertShowing("Documents", in: app)
        XCTAssertFalse(folderRow(named: "Images", in: app).exists)

        goBack(in: app)

        // One level up is the tree the reader came from, with its other folders back in view.
        XCTAssertTrue(folderRow(named: "Images", in: app).waitForExistence(timeout: 3))
    }

    /// Choosing a folder from the tree opens it with everything above it already on the stack, so
    /// going back steps up one level at a time rather than all the way out at once.
    @MainActor
    func testANestedFolderIsEnteredWithItsAncestorsBehindIt() throws {
        let app = launchArchive()
        showFolderTree(in: app)

        let documents = folderRow(named: "Documents", in: app)
        XCTAssertTrue(documents.waitForExistence(timeout: 5))
        // Open the folder's own row disclosure so the nested folder is reachable from the tree.
        let disclosure = app.buttons["Expand"].firstMatch
        try XCTSkipUnless(disclosure.waitForExistence(timeout: 3), "No expandable folder on screen")
        disclosure.tap()

        let drafts = folderRow(named: "Drafts", in: app)
        XCTAssertTrue(drafts.waitForExistence(timeout: 3))
        drafts.tap()
        assertShowing("Drafts", in: app)

        goBack(in: app)

        // Documents, not the tree: the jump landed with its parent underneath it.
        assertShowing("Documents", in: app)
    }

    /// The gear belongs to the folder tree, and comes back with it.
    ///
    /// It used to be withdrawn by asking the canonical state whether the stack was empty. A toolbar
    /// stated on a stack's root content is the root's bar already, so the question bought nothing
    /// and cost the gear its place in the pop: the bar came back first and the gear a moment after.
    @MainActor
    func testTheSettingsGearBelongsToTheFolderTreeAlone() {
        let app = launchArchive()
        showFolderTree(in: app)

        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        let documents = folderRow(named: "Documents", in: app)
        XCTAssertTrue(documents.waitForExistence(timeout: 5))
        documents.tap()
        assertShowing("Documents", in: app)

        // A folder's own list has its own controls; Settings is not among them.
        XCTAssertFalse(settings.exists)

        goBack(in: app)

        XCTAssertTrue(settings.waitForExistence(timeout: 3))
    }

    /// Each area keeps its own depth, which is what a tab bar does everywhere else on the system.
    @MainActor
    func testLeavingAnAreaAndComingBackKeepsItsDepth() {
        let app = launchArchive()
        showFolderTree(in: app)
        let tags = tab(labeled: "Tags", in: app)
        XCTAssertTrue(tags.waitForExistence(timeout: 3))

        let documents = folderRow(named: "Documents", in: app)
        XCTAssertTrue(documents.waitForExistence(timeout: 5))
        documents.tap()
        assertShowing("Documents", in: app)

        // The other area, showing its own name and not the one left behind.
        tags.tap()
        assertShowing("Tags", in: app)

        tab(labeled: "Folders", in: app).tap()

        assertShowing("Documents", in: app)
    }

    /// At a width with a sidebar, choosing there shows it in the column beside it. The sidebar is
    /// not a second place the reader can be; it is one projection of the same state.
    ///
}
