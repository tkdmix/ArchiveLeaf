import Foundation
import XCTest
@testable import ArchiveLeaf

final class SharedURLInterpretationTests: XCTestCase {
    func testAcceptsAPlainURL() throws {
        XCTAssertEqual(
            SharedURLInterpretation.webURL(from: "https://example.com/article?id=7"),
            try XCTUnwrap(URL(string: "https://example.com/article?id=7"))
        )
    }

    func testFindsAURLOnItsOwnLineWhenAProviderAddsATitle() throws {
        XCTAssertEqual(
            SharedURLInterpretation.webURL(from: "Example article\nhttps://example.com/article\n"),
            try XCTUnwrap(URL(string: "https://example.com/article"))
        )
    }

    func testIgnoresACompanionTitleAfterTheURL() throws {
        XCTAssertEqual(
            SharedURLInterpretation.webURL(from: "https://example.com/article\nExample article"),
            try XCTUnwrap(URL(string: "https://example.com/article"))
        )
    }

    func testDoesNotTreatOrdinaryTextContainingALinkAsAPageShare() {
        XCTAssertNil(
            SharedURLInterpretation.webURL(from: "Read https://example.com when you have time")
        )
    }

    func testRejectsNonWebSchemes() {
        XCTAssertNil(SharedURLInterpretation.webURL(from: "Example\nfile:///private/tmp/note.txt"))
        XCTAssertNil(SharedURLInterpretation.webURL(from: "javascript:alert(1)"))
    }
}
