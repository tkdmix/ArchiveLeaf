import XCTest

/// A long press offers the same commands wherever the item is met.
///
/// Folders, tags and Favorites are three ways of reaching the same file, and each list had grown its
/// own idea of what could be done to a row: Favorites offered two commands, a tag's list none at
/// all. This is the test that notices the next time one of them drifts.
///
/// The commands are checked by their words because a menu item has no identifier to check instead;
/// the app is launched in English so that the words are the ones written here.
final class ItemMenuUITests: XCTestCase {
    /// The commands every file row offers, in the order the bar of actions puts them.
    private let fileCommands = ["Move To…", "Rename", "Move to Trash"]

    @MainActor
    func testAFileInAFolderOffersTheWholeMenu() {
        let app = launchArchive()
        showFolderTree(in: app)
        folderRow(named: "Documents", in: app).tap()

        pressAndHold(row("item-row-Welcome.md", in: app))

        for command in fileCommands {
            XCTAssertTrue(
                app.buttons[command].waitForExistence(timeout: 3),
                "A file in a folder offers no \(command)"
            )
        }
    }

    /// The same file, reached through Favorites rather than through its folder.
    @MainActor
    func testTheSameFileInFavoritesOffersTheSameMenu() {
        let app = launchArchive()
        let favorites = tab(labeled: "Favorites", in: app)
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()

        pressAndHold(row("item-row-Welcome.md", in: app))

        for command in fileCommands {
            XCTAssertTrue(
                app.buttons[command].waitForExistence(timeout: 3),
                "A file in Favorites offers no \(command)"
            )
        }
    }

    /// A folder takes the three commands that apply to a folder, and nothing stands in for the ones
    /// that do not. Making a folder inside this one is not among them: on iOS that is reached by
    /// opening the folder and pressing New Folder there, which is where the reader already is when
    /// they want it. The Mac keeps it in the menu because its outline shows the whole tree without
    /// ever opening a folder to stand inside.
    @MainActor
    func testAFolderInTheTreeOffersTheCommandsAFolderCanTake() {
        let app = launchArchive()
        showFolderTree(in: app)

        pressAndHold(folderRow(named: "Documents", in: app))

        for command in ["Move To…", "Rename", "Move to Trash"] {
            XCTAssertTrue(
                app.buttons[command].waitForExistence(timeout: 3),
                "A folder offers no \(command)"
            )
        }
        // Nothing that only a file can take, and nothing put there to fill the gap.
        XCTAssertFalse(app.buttons["Add to Favorites"].exists)
        XCTAssertFalse(app.buttons["New Folder Inside"].exists)
    }

    @MainActor
    private func pressAndHold(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.press(forDuration: 1.0)
    }
}
