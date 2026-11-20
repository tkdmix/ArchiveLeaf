import Foundation
import XCTest
@testable import ArchiveLeaf

final class NameSuggestionTests: XCTestCase {
    func testUsesTheFirstLine() {
        XCTAssertEqual(
            NameSuggestion.fileName(forSharedText: "Meeting notes\n\nDiscussed the schedule.\n"),
            "Meeting notes"
        )
    }

    func testReplacesCharactersAFileNameCannotHold() {
        XCTAssertEqual(
            NameSuggestion.fileName(forSharedText: "2026/08/07: standup"),
            "2026-08-07- standup"
        )
    }

    func testTruncatesALongFirstLineWithoutLeavingTrailingSpace() {
        let text = String(repeating: "a", count: NameSuggestion.maximumLength) + " tail"
        let name = NameSuggestion.fileName(forSharedText: text)

        XCTAssertEqual(name.count, NameSuggestion.maximumLength)
        XCTAssertFalse(name.hasSuffix(" "))
    }

    func testFallsBackWhenThereIsNoUsableFirstLine() {
        // Naming still has to produce something the user can accept or replace.
        XCTAssertFalse(NameSuggestion.fileName(forSharedText: "\n\n   \n").isEmpty)
        XCTAssertFalse(NameSuggestion.fileName(forSharedText: "").isEmpty)
    }
}
