import CoreGraphics
import XCTest
@testable import ArchiveLeaf

final class PDFZoomCommandTests: XCTestCase {
    private let letter = CGSize(width: 612, height: 792)

    func testFitPageUsesWhicheverSideRunsOutFirst() {
        let wide = PDFZoomCommand.fitPage.scaleFactor(
            pageSize: letter,
            rotation: 0,
            available: CGSize(width: 1_600, height: 396)
        )
        let narrow = PDFZoomCommand.fitPage.scaleFactor(
            pageSize: letter,
            rotation: 0,
            available: CGSize(width: 306, height: 2_000)
        )

        XCTAssertEqual(try XCTUnwrap(wide), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(narrow), 0.5, accuracy: 0.0001)
    }

    func testFitWidthIgnoresTheHeightThePageIsReadThrough() {
        let scale = PDFZoomCommand.fitWidth.scaleFactor(
            pageSize: letter,
            rotation: 0,
            available: CGSize(width: 1_224, height: 100)
        )

        XCTAssertEqual(try XCTUnwrap(scale), 2, accuracy: 0.0001)
    }

    func testAQuarterTurnedPageIsMeasuredAcrossTheSideItIsReadOn() {
        let upright = PDFZoomCommand.fitWidth.scaleFactor(
            pageSize: letter,
            rotation: 0,
            available: CGSize(width: 612, height: 792)
        )
        let turned = PDFZoomCommand.fitWidth.scaleFactor(
            pageSize: letter,
            rotation: 90,
            available: CGSize(width: 612, height: 792)
        )

        XCTAssertEqual(try XCTUnwrap(upright), 1, accuracy: 0.0001)
        // Turned, the 792-point side is the width, so the same pane fits less of it.
        XCTAssertEqual(try XCTUnwrap(turned), 612.0 / 792.0, accuracy: 0.0001)
    }

    func testFittingAPageAsksForTheWholePage() {
        // Wherever the reader had scrolled to, and at whatever magnification.
        let rect = PDFZoomCommand.fitPage.destinationRect(
            pageBounds: CGRect(origin: .zero, size: letter),
            visibleTopInPage: 300,
            paneHeight: 400,
            scaleFactor: 0.5
        )

        XCTAssertEqual(rect, CGRect(origin: .zero, size: letter))
    }

    func testFittingTheWidthKeepsThePlaceAndTakesOutTheSidewaysDrift() {
        let bounds = CGRect(origin: .zero, size: letter)

        let rect = PDFZoomCommand.fitWidth.destinationRect(
            pageBounds: bounds,
            visibleTopInPage: 600,
            paneHeight: 396,
            scaleFactor: 2
        )

        // 396 points of pane at twice the size is 198 points of page, ending where it was. The
        // rect's centred zero-width x leaves PDFKit's page-centred horizontal position intact.
        XCTAssertEqual(rect.minX, bounds.midX, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.maxY, 600, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 198, accuracy: 0.0001)
    }

    func testFittingTheWidthNearAnEdgeStaysOnTheSamePage() {
        let bounds = CGRect(origin: .zero, size: letter)

        let atTheTop = PDFZoomCommand.fitWidth.destinationRect(
            pageBounds: bounds,
            visibleTopInPage: 5_000,
            paneHeight: 396,
            scaleFactor: 2
        )
        let atTheBottom = PDFZoomCommand.fitWidth.destinationRect(
            pageBounds: bounds,
            visibleTopInPage: -5_000,
            paneHeight: 396,
            scaleFactor: 2
        )

        XCTAssertEqual(atTheTop.maxY, bounds.maxY, accuracy: 0.0001)
        XCTAssertEqual(atTheBottom.minY, bounds.minY, accuracy: 0.0001)
    }

    func testFittingTheWidthAsksForTheWholePageWhenItAllFits() {
        // Nothing to keep the reader's place within: the page is shorter than the pane shows.
        let rect = PDFZoomCommand.fitWidth.destinationRect(
            pageBounds: CGRect(origin: .zero, size: letter),
            visibleTopInPage: 400,
            paneHeight: 1_600,
            scaleFactor: 1
        )

        XCTAssertEqual(rect, CGRect(origin: .zero, size: letter))
    }

    func testCorrectedHorizontalOffsetMovesThePageCentreToThePaneCentre() {
        let corrected = PDFZoomCommand.correctedHorizontalOffset(
            currentOffset: 40,
            pageMidX: 406,
            paneMidX: 375,
            minimumOffset: 0,
            maximumOffset: 200
        )

        XCTAssertEqual(corrected, 71)
    }

    func testCorrectedHorizontalOffsetClampsButDoesNotChangeTheVerticalPosition() {
        let corrected = PDFZoomCommand.correctedHorizontalOffset(
            currentOffset: 190,
            pageMidX: 500,
            paneMidX: 375,
            minimumOffset: 0,
            maximumOffset: 200
        )

        XCTAssertEqual(corrected, 200)
    }

    func testCorrectedHorizontalOffsetRejectsAnInvalidRange() {
        XCTAssertNil(PDFZoomCommand.correctedHorizontalOffset(
            currentOffset: 0,
            pageMidX: 0,
            paneMidX: 0,
            minimumOffset: 2,
            maximumOffset: 1
        ))
    }

    func testReportsNothingToScaleAgainstRatherThanDividingByZero() {
        XCTAssertNil(PDFZoomCommand.fitWidth.scaleFactor(
            pageSize: .zero,
            rotation: 0,
            available: CGSize(width: 100, height: 100)
        ))
        XCTAssertNil(PDFZoomCommand.fitWidth.scaleFactor(
            pageSize: letter,
            rotation: 0,
            available: .zero
        ))
    }
}
