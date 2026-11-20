import XCTest

/// How every UI test drives the app.
///
/// The three tests that existed before this file had each memorised the interface in their own
/// words — a tab called "Archive", a Restore button reached by swiping right, a folder addressed by
/// its name. All three went red as the app moved, and none of them was noticed, because the UI
/// scheme was not part of the routine run. Keeping the driving in one place means the next change
/// to a control is one edit rather than three, and it is obvious where to make it.
extension XCTestCase {
    /// Never the reader's own archive. Every UI test runs against the in-memory sample, so opening
    /// folders, restoring, and deleting cannot touch anything in iCloud.
    @MainActor
    func launchArchive(
        language: String = "en",
        locale: String = "en_US",
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ARCHIVELEAF_DATA_SOURCE"] = "memory"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    /// The archive opens inside its unsorted-file list, one level below the tree. Step up so that
    /// what a test drives is the tree, whatever the app happens to open on.
    @MainActor
    func showFolderTree(in app: XCUIApplication) {
        guard folderRow(named: "Documents", in: app).waitForExistence(timeout: 5) == false else {
            return
        }
        let backButton = backButton(in: app)
        if backButton.waitForExistence(timeout: 2), backButton.isHittable {
            backButton.tap()
        }
    }

    /// The system's own back control.
    ///
    /// UIKit gives it the identifier `BackButton` on iOS 26 and nothing at all on iOS 17, where its
    /// label is the name of the screen behind it — which is wording, and translated. So: the
    /// identifier where there is one, and otherwise the first button in the navigation bar, which
    /// is where back has always been.
    @MainActor
    func backButton(in app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["BackButton"].firstMatch
        if named.exists { return named }
        return app.navigationBars.firstMatch.buttons.element(boundBy: 0)
    }

    /// A folder's row, addressed by identifier rather than by the words on it: a label is wording,
    /// and wording changes — and is translated.
    @MainActor
    func folderRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        row("folder-row-\(name)", in: app)
    }

    /// Where the reader is, read from the pane's own title.
    ///
    /// It used to be read from the navigation bar's name. The name moved out of the bar and into
    /// the content — deliberately, and written down in `The four primary areas` — and the bar is
    /// still there, holding controls and no name at all. Asking the bar what it is called now
    /// answers nothing, which is what turned three of these tests red at once.
    ///
    /// The whole screen carries exactly one content title, so this needs no further qualification.
    @MainActor
    func contentTitle(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["content-title"].firstMatch
    }

    /// Whether the pane on screen is the one named — asked of the title, not of the bar.
    @MainActor
    func assertShowing(
        _ name: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let title = contentTitle(in: app)
        XCTAssertTrue(
            title.waitForExistence(timeout: timeout),
            "No pane title on screen while expecting \(name)",
            file: file,
            line: line
        )
        XCTAssertEqual(title.label, name, file: file, line: line)
    }

    /// A tag's row in the tag tree, addressed the same way a folder's row is.
    @MainActor
    func tagRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        row("tag-row-\(name)", in: app)
    }

    /// The part of a row that can actually be pressed.
    ///
    /// An identifier put on a row reaches its pieces as well — the icon, the badge — and the first
    /// of those in the tree is often a picture nobody can tap. Taking the first that is hittable
    /// asks for the row rather than for whichever piece happens to come first.
    @MainActor
    func row(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        guard matches.firstMatch.waitForExistence(timeout: 5) else { return matches.firstMatch }
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    /// A tab, addressed by the word on it. Its identifier is the name of its symbol — `tag`, `star`
    /// — which says nothing about where it goes and would break the moment a symbol changed.
    @MainActor
    func tab(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// The system's own back control. UIKit gives it a stable identifier, so it does not have to be
    /// found by its position or by its wording — the wording is the name of the screen behind it.
    @MainActor
    func goBack(in app: XCUIApplication) {
        let button = backButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    /// Trash, from its tab. Every iOS device has the tab bar now: the iPad's sidebar was dropped.
    @MainActor
    func openTrash(in app: XCUIApplication, tabLabel: String = "Trash") {
        let tabButton = tab(labeled: tabLabel, in: app)
        XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
        tabButton.tap()
    }

    /// A named iPad reader pane. Querying the accessibility tree rather than assuming a
    /// UIKit element type keeps this stable across the system's compact and split presentations.
    @MainActor
    func tabletPane(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

}
