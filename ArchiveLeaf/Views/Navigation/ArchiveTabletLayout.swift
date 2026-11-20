import CoreGraphics

/// The iPad reader needs enough room for both a useful browser and a useful document. The decision
/// is based on the container supplied by SwiftUI rather than the device's screen, so Split View and
/// Stage Manager fall back to the compact reader as soon as their actual window becomes too small.
enum ArchiveTabletLayout {
    static let minimumTwoPaneWidth: CGFloat = 900
    static let browserWidth: CGFloat = 380

    static func usesTwoPane(availableSize: CGSize, isRegularWidth: Bool) -> Bool {
        isRegularWidth
            && availableSize.width >= minimumTwoPaneWidth
            && availableSize.width > availableSize.height
    }
}
