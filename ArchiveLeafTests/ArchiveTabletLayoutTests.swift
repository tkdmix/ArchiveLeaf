import CoreGraphics
import XCTest
@testable import ArchiveLeaf

final class ArchiveTabletLayoutTests: XCTestCase {
    func testWideLandscapeRegularContainerUsesTwoPanes() {
        XCTAssertTrue(
            ArchiveTabletLayout.usesTwoPane(
                availableSize: CGSize(width: 1_024, height: 768),
                isRegularWidth: true
            )
        )
    }

    func testPortraitAndNarrowContainersStayCompact() {
        XCTAssertFalse(
            ArchiveTabletLayout.usesTwoPane(
                availableSize: CGSize(width: 768, height: 1_024),
                isRegularWidth: true
            )
        )
        XCTAssertFalse(
            ArchiveTabletLayout.usesTwoPane(
                availableSize: CGSize(width: 899, height: 600),
                isRegularWidth: true
            )
        )
    }

    func testCompactSizeClassStaysCompactEvenWhenWide() {
        XCTAssertFalse(
            ArchiveTabletLayout.usesTwoPane(
                availableSize: CGSize(width: 1_200, height: 800),
                isRegularWidth: false
            )
        )
    }
}
