import Foundation
import XCTest
@testable import ArchiveLeaf

final class ArchiveWriteBatchTests: XCTestCase {
    private let megabyte: Int64 = 1_024 * 1_024

    /// The case this rule exists for. A bookmark is about 270 bytes, so a fixed count of twenty sent
    /// five kilobytes per round trip and an export of a thousand took fifty of them.
    func testSmallPayloadsFillTheRecordCount() {
        let bookmarks = Array(repeating: Int64(268), count: 1_000)

        let batches = ArchiveWriteBatch.split(
            bookmarks,
            maximumCount: 200,
            maximumBytes: 100 * megabyte,
            bytes: { $0 }
        )

        XCTAssertEqual(batches.map(\.count), [200, 200, 200, 200, 200])
    }

    /// An ordinary selection of photos is unchanged: it fits in one request, as it did before.
    func testAnOrdinarySelectionOfImagesStaysInOneRequest() {
        let images = Array(repeating: 3 * megabyte, count: 20)

        let batches = ArchiveWriteBatch.split(
            images,
            maximumCount: 200,
            maximumBytes: 100 * megabyte,
            bytes: { $0 }
        )

        XCTAssertEqual(batches.count, 1)
    }

    func testSplitsWhenTheBudgetWouldBeExceeded() {
        let videos = Array(repeating: 60 * megabyte, count: 3)

        let batches = ArchiveWriteBatch.split(
            videos,
            maximumCount: 200,
            maximumBytes: 100 * megabyte,
            bytes: { $0 }
        )

        XCTAssertEqual(batches.map(\.count), [1, 1, 1])
    }

    /// The budget decides grouping, not what may be written. Refusing a file happens earlier, and
    /// somewhere else.
    func testAnItemLargerThanTheBudgetIsWrittenOnItsOwn() {
        let sizes: [Int64] = [megabyte, 500 * megabyte, megabyte]

        let batches = ArchiveWriteBatch.split(
            sizes,
            maximumCount: 200,
            maximumBytes: 100 * megabyte,
            bytes: { $0 }
        )

        XCTAssertEqual(batches, [[megabyte], [500 * megabyte], [megabyte]])
    }

    func testKeepsTheOrderItWasGiven() {
        let sizes: [Int64] = Array(1...10).map(Int64.init)

        let batches = ArchiveWriteBatch.split(
            sizes,
            maximumCount: 3,
            maximumBytes: .max,
            bytes: { $0 }
        )

        XCTAssertEqual(batches.flatMap { $0 }, sizes)
        XCTAssertEqual(batches.map(\.count), [3, 3, 3, 1])
    }

    func testEmptyInputProducesNoBatches() {
        XCTAssertTrue(
            ArchiveWriteBatch.split(
                [Int64](),
                maximumCount: 200,
                maximumBytes: 100 * megabyte,
                bytes: { $0 }
            ).isEmpty
        )
    }

    /// A size that cannot be believed must not silently drop a file. Sizes come from the file system
    /// and from records written by earlier versions.
    func testTreatsAnImpossibleSizeAsNothingRatherThanLosingTheItem() {
        let sizes: [Int64] = [-1, .max, 1]

        let batches = ArchiveWriteBatch.split(
            sizes,
            maximumCount: 200,
            maximumBytes: 100 * megabyte,
            bytes: { $0 }
        )

        XCTAssertEqual(batches.flatMap { $0 }.count, 3)
    }
}
