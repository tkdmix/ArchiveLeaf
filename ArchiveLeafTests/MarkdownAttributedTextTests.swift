import Foundation
import XCTest
@testable import ArchiveLeaf

final class MarkdownAttributedTextTests: XCTestCase {
    func testSeparatesHeadingFromFollowingParagraph() {
        let source = "# Welcome to ArchiveLeaf\n\nSelect an imported file to view its immutable content.\n"

        let text = String(MarkdownAttributedText.attributedString(from: source).characters)

        XCTAssertEqual(
            text,
            "Welcome to ArchiveLeaf\n\nSelect an imported file to view its immutable content."
        )
    }

    func testKeepsConsecutiveBlocksApart() {
        let source = "First paragraph.\n\nSecond paragraph.\n\n## Section\n\nThird paragraph.\n"

        let text = String(MarkdownAttributedText.attributedString(from: source).characters)

        XCTAssertEqual(
            text,
            "First paragraph.\n\nSecond paragraph.\n\nSection\n\nThird paragraph."
        )
    }

    func testRestoresListMarkersAndKeepsItemsOfOneListAdjacent() {
        let source = "- alpha\n- beta\n\n1. first\n2. second\n"

        let text = String(MarkdownAttributedText.attributedString(from: source).characters)

        XCTAssertEqual(text, "• alpha\n• beta\n\n1. first\n2. second")
    }

    func testAppliesHeadingFontOnlyToTheHeadingBlock() throws {
        let source = "# Title\n\nBody text.\n"

        let attributed = MarkdownAttributedText.attributedString(from: source)

        // The platform font, not SwiftUI's: the document is drawn by a text view, and only this
        // one survives the crossing into `NSAttributedString`.
        let headingRun = try XCTUnwrap(attributed.runs.first)
        let bodyRun = try XCTUnwrap(attributed.runs.last)
        #if os(macOS)
        let appKitText = NSAttributedString(attributed)
        let heading = try XCTUnwrap(
            appKitText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        let body = try XCTUnwrap(
            appKitText.attribute(.font, at: appKitText.length - 1, effectiveRange: nil) as? NSFont
        )
        #else
        let heading = try XCTUnwrap(headingRun.uiKit.font)
        let body = try XCTUnwrap(bodyRun.uiKit.font)
        #endif
        XCTAssertGreaterThan(heading.pointSize, body.pointSize)
    }

    func testFallsBackToTheRawSourceWhenNothingParses() {
        let text = String(MarkdownAttributedText.attributedString(from: "").characters)

        XCTAssertEqual(text, "")
    }
}
