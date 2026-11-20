import Foundation
import XCTest
@testable import ArchiveLeaf

final class ArchiveTrashOrderTests: XCTestCase {
    /// What was thrown away last is at the top when the Trash opens, and folders and files are in
    /// one list rather than in two heaps.
    func testDiscardedOrderPutsTheMostRecentFirstAcrossBothKinds() {
        let old = file("old.txt", discardedAt: 100)
        let middle = folder("Middle", discardedAt: 200)
        let newest = file("new.txt", discardedAt: 300)

        let ordered = ArchiveTrashArrangement.ordered(
            [old, newest, middle],
            by: .discarded,
            ascending: false
        )

        XCTAssertEqual(ordered.map(\.listedName), ["new.txt", "Middle", "old.txt"])
    }

    /// Turning the order around gives the oldest first, which is what a reader asks for when they
    /// are looking for something they threw away a while ago.
    func testTurningTheDiscardedOrderAroundGivesTheOldestFirst() {
        let old = file("old.txt", discardedAt: 100)
        let newest = folder("New", discardedAt: 300)

        let ordered = ArchiveTrashArrangement.ordered(
            [newest, old],
            by: .discarded,
            ascending: true
        )

        XCTAssertEqual(ordered.map(\.listedName), ["old.txt", "New"])
    }

    /// By name, a folder and a file are simply names: nothing is grouped by kind here.
    func testNameOrderIgnoresWhichKindEachItemIs() {
        let apple = file("apple.txt", discardedAt: 100)
        let banana = folder("Banana", discardedAt: 300)
        let cherry = file("cherry.txt", discardedAt: 200)

        let ordered = ArchiveTrashArrangement.ordered(
            [cherry, apple, banana],
            by: .name,
            ascending: true
        )

        XCTAssertEqual(ordered.map(\.listedName), ["apple.txt", "Banana", "cherry.txt"])
    }

    /// Two items that compare the same keep a settled order, so a redraw cannot shuffle them.
    func testItemsThatCompareTheSameKeepASettledOrder() {
        let first = file("same.txt", discardedAt: 100)
        let second = folder("Same", discardedAt: 100)

        let once = ArchiveTrashArrangement.ordered([first, second], by: .discarded, ascending: false)
        let again = ArchiveTrashArrangement.ordered([second, first], by: .discarded, ascending: false)

        XCTAssertEqual(once.map(\.id), again.map(\.id))
    }

    /// Every visit begins with what was thrown away last: the order is not remembered anywhere, and
    /// the mode each list starts in says so.
    func testEachOrderBeginsInTheDirectionAReaderMeans() {
        XCTAssertFalse(ArchiveTrashOrder.discarded.beginsAscending)
        XCTAssertTrue(ArchiveTrashOrder.name.beginsAscending)
    }

    private func file(_ name: String, discardedAt seconds: TimeInterval) -> ArchiveItem {
        var file = ArchiveFile(originalFileName: name, detectedFormat: .plainText)
        file.isTrashed = true
        file.trashedAt = Date(timeIntervalSince1970: seconds)
        return .file(file)
    }

    private func folder(_ name: String, discardedAt seconds: TimeInterval) -> ArchiveItem {
        var folder = ArchiveFolder(name: name)
        folder.isTrashed = true
        folder.trashedAt = Date(timeIntervalSince1970: seconds)
        return .folder(folder)
    }
}
