import CoreGraphics

/// What a reader means by a magnification, said in the two ways that carry between documents.
///
/// Not the picture viewer's four. A page is not a picture: "actual size" is the paper's size rather
/// than the screen's, and stepping in and out is what the pinch is already for.
enum PDFZoomCommand {
    case fitPage
    case fitWidth

    /// The magnification this command asks for, or `nil` when there is nothing to measure against.
    ///
    /// Measured from the page rather than asked of PDFKit. `scaleFactorForSizeToFit` answers for
    /// the display mode as a whole, which in a continuous column is the width — so it cannot say
    /// what fitting the whole page means. The page's own box can, once its rotation has been
    /// applied: a page turned a quarter turn is read across the side the stored numbers call its
    /// height.
    func scaleFactor(
        pageSize: CGSize,
        rotation: Int,
        available: CGSize
    ) -> CGFloat? {
        let isQuarterTurned = (rotation / 90) % 2 != 0
        let visible = isQuarterTurned
            ? CGSize(width: pageSize.height, height: pageSize.width)
            : pageSize
        guard visible.width > 0, visible.height > 0,
              available.width > 0, available.height > 0 else {
            return nil
        }
        switch self {
        case .fitPage:
            return min(available.width / visible.width, available.height / visible.height)
        case .fitWidth:
            return available.width / visible.width
        }
    }

    /// Where the continuous pane should be left looking once the magnification has been applied.
    ///
    /// A magnification alone is half the answer. PDFKit keeps whatever the pane was scrolled to,
    /// so a page fitted while the reader was halfway down it stays halfway down it: the whole page
    /// now fits, and the top of it is still off the top of the pane. Fitting a page means seeing
    /// that page.
    ///
    /// Fitting the width is the other way round. There the reader is reading, and moving them to
    /// the top of the page would lose their place, so only the sideways drift is taken out — the
    /// page is returned to the width-fit origin at the height they were already reading.
    ///
    /// In page coordinates, where y grows upward.
    func destinationRect(
        pageBounds: CGRect,
        visibleTopInPage: CGFloat,
        paneHeight: CGFloat,
        scaleFactor: CGFloat
    ) -> CGRect {
        guard case .fitWidth = self, scaleFactor > 0 else { return pageBounds }
        let visibleHeight = paneHeight / scaleFactor
        guard visibleHeight > 0, visibleHeight < pageBounds.height else { return pageBounds }
        // Clamped to the page: a strip reaching past either edge would scroll the neighbouring
        // page into view instead of the one being read.
        let top = min(max(visibleTopInPage, pageBounds.minY + visibleHeight), pageBounds.maxY)
        return CGRect(
            // A centred zero-width rect limits this follow-up navigation to restoring the
            // vertical reading position. The platform helper corrects mixed-page x afterwards.
            x: pageBounds.midX,
            y: top - visibleHeight,
            width: 0,
            height: visibleHeight
        )
    }

    /// Corrects a scroll position by the page's measured horizontal displacement, without
    /// allowing the result outside the scroll view's legal range.
    ///
    /// Keeping this arithmetic independent of PDFKit and UIKit/AppKit makes the one necessary
    /// implementation-detail workaround testable.
    static func correctedHorizontalOffset(
        currentOffset: CGFloat,
        pageMidX: CGFloat,
        paneMidX: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat
    ) -> CGFloat? {
        guard currentOffset.isFinite,
              pageMidX.isFinite,
              paneMidX.isFinite,
              minimumOffset.isFinite,
              maximumOffset.isFinite,
              minimumOffset <= maximumOffset else {
            return nil
        }
        return min(
            max(currentOffset + (pageMidX - paneMidX), minimumOffset),
            maximumOffset
        )
    }
}
