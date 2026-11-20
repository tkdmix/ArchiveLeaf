import XCTest
@testable import ArchiveLeaf

final class DocumentSearchTests: XCTestCase {
    func testFindsCaseAndDiacriticInsensitiveNonOverlappingMatches() {
        let ranges = DocumentSearch().ranges(of: "cafe", in: "Café cafe cafeteria")

        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 4),
            NSRange(location: 10, length: 4)
        ])
    }

    func testEmptyQueryHasNoMatches() {
        XCTAssertTrue(DocumentSearch().ranges(of: "", in: "ArchiveLeaf").isEmpty)
    }
}
