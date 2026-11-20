import Foundation
import XCTest
@testable import ArchiveLeaf

final class BookmarkDocumentNamingTests: XCTestCase {
    func testUsesHostWhenItIsAvailable() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/first"))

        XCTAssertEqual(BookmarkDocument.uniqueTitle(for: url, among: []), "example.com")
    }

    func testAddsFinderStyleSuffixForAnotherURLFromTheSameHost() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/second"))

        XCTAssertEqual(
            BookmarkDocument.uniqueTitle(for: url, among: ["example.com", "example.com 2"]),
            "example.com 3"
        )
    }

    func testNameCollisionComparisonMatchesArchiveNormalization() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/second"))

        XCTAssertEqual(
            BookmarkDocument.uniqueTitle(for: url, among: [" EXAMPLE.COM "]),
            "example.com 2"
        )
    }
}
