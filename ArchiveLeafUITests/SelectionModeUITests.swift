import XCTest

/// Choosing several rows at once, in every list that has rows.
///
/// It began in the folder list alone, which meant the same file could be picked in one place and
/// not in another. These are the lists that were left out; the bar they raise is the same bar, and
/// which of its actions are live is `ArchiveItemSelection`'s judgement, tested on its own.
final class SelectionModeUITests: XCTestCase {
    @MainActor
    func testFavoritesCanChooseSeveralAndRaisesTheArchivesActions() {
        let app = launchArchive()
        tab(labeled: "Favorites", in: app).tap()

        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        row("item-row-Welcome.md", in: app).tap()

        // The archive's four verbs, in the order of the tabs. The file is already a favorite, so
        // the star offers to take it off.
        assertArchiveActions(in: app)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    /// The same file again, reached through the tag it carries.
    @MainActor
    func testATagsFilesCanBeChosenTheSameWay() {
        let app = launchArchive()
        tab(labeled: "Tags", in: app).tap()

        let notes = tagRow(named: "Notes", in: app)
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()

        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        row("item-row-Welcome.md", in: app).tap()

        assertArchiveActions(in: app)
    }

    /// Compact toolbars can put their trailing commands in the system's More menu.
    /// Every command must remain available, whether it is in the bar or in that menu.
    @MainActor
    private func assertArchiveActions(in app: XCUIApplication) {
        let actions = ["Move", "Unfavorite", "Tags", "Trash"]
        let overflowed = actions.filter { !app.buttons[$0].exists }
        for action in actions where !overflowed.contains(action) {
            XCTAssertTrue(app.buttons[action].isHittable, "Cannot reach \(action) in the bar")
            XCTAssertTrue(app.buttons[action].isEnabled, "Cannot use \(action) in the bar")
        }
        guard !overflowed.isEmpty else { return }
        // iOS 27.2 gives bottom-bar overflow its own identifier; earlier systems
        // expose the shared toolbar identifier. Both still lead to the real commands.
        let overflowButtons = app.buttons.matching(NSPredicate(
            format: "identifier IN %@",
            ["BottomOverflowBarButtonItem", "ToolbarOverflowBarButtonItem"]
        ))
        guard overflowButtons.firstMatch.waitForExistence(timeout: 3) else {
            // These UI tests always launch the synthetic in-memory shelf. Preserve its
            // accessibility tree when a new OS changes the system toolbar representation.
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Synthetic selection accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic selection toolbar"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("Missing selection commands: \(overflowed.joined(separator: ", ")); no toolbar overflow menu")
            return
        }
        let bottomOverflow = app.buttons["BottomOverflowBarButtonItem"]
        let more = bottomOverflow.exists
            ? bottomOverflow
            : app.buttons["ToolbarOverflowBarButtonItem"]
        more.tap()
        for action in overflowed {
            let button = app.buttons[action]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "No \(action) in toolbar overflow")
            XCTAssertTrue(button.isHittable, "Cannot reach \(action) in toolbar overflow")
            XCTAssertTrue(button.isEnabled, "Cannot use \(action) in toolbar overflow")
        }
    }

    /// The Trash raises two verbs rather than four: a discarded file has nowhere to be moved to and
    /// no tag worth changing until it is back.
    @MainActor
    func testTrashCanChooseSeveralAndRaisesRestoreAndDelete() {
        let app = launchArchive(environment: ["ARCHIVELEAF_UI_TEST_TRASH": "1"])
        openTrash(in: app)

        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        row("item-row-Welcome.md", in: app).tap()

        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        // Nothing that belongs to the archive.
        XCTAssertFalse(app.buttons["Move"].exists)
        XCTAssertFalse(app.buttons["Tags"].exists)
    }
}
