import Foundation
import XCTest
@testable import ArchiveLeaf

#if os(macOS)
import AppKit

/// The Mac's half of a document's links.
///
/// The iOS half is covered end to end by `BrowserFailureUITests`, which opens a document, presses a
/// link in it, and waits for the archive's own browser. The Mac has no equivalent: its UI test
/// target builds as Mac Catalyst and cannot be signed here. So what can be checked without a window
/// is checked without one — that the delegate hands the URL out and claims the click, rather than
/// letting it fall through to the system browser.
///
/// What this does not prove is that AppKit calls the delegate at all. That has to be tried by hand
/// in the running Mac app, and is the reason this file says so out loud.
@MainActor
final class DocumentTextViewLinkTests: XCTestCase {
    func testAClickedLinkIsHandedOutAndNotLeftToTheSystem() {
        var opened: [URL] = []
        let coordinator = DocumentTextView.Coordinator { opened.append($0) }
        let textView = NSTextView()
        let url = URL(string: "https://example.com/page")!

        let handled = coordinator.textView(textView, clickedOnLink: url, at: 0)

        XCTAssertTrue(handled, "Returning false hands the link to the system browser")
        XCTAssertEqual(opened, [url])
    }

    /// A text view may carry its links as strings rather than as URLs, depending on how the
    /// attributed string was built.
    func testALinkWrittenAsAStringIsUnderstood() {
        var opened: [URL] = []
        let coordinator = DocumentTextView.Coordinator { opened.append($0) }

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: "https://example.com/page",
            at: 0
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(opened, [URL(string: "https://example.com/page")!])
    }

    /// Nothing usable is nothing to open, and the click is left alone rather than swallowed.
    func testSomethingThatIsNotAURLIsLeftAlone() {
        var opened: [URL] = []
        let coordinator = DocumentTextView.Coordinator { opened.append($0) }

        let handled = coordinator.textView(NSTextView(), clickedOnLink: 42, at: 0)

        XCTAssertFalse(handled)
        XCTAssertTrue(opened.isEmpty)
    }
}
#endif
