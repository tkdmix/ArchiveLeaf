import Foundation

/// A destination the pointing device cannot name exactly, asked for from the toolbar and carried
/// out once. Stepping in and out is here too because the Mac window keeps buttons for it.
enum ImageZoomCommand {
    case fit
    case actualSize
    case zoomIn
    case zoomOut

    /// Applied per press of a step button, and as the factor a double tap or smart zoom jumps by.
    static let step = 1.25
    static let doubleTapFactor = 3.0
    /// How far past fitting the picture can be enlarged, and never less than actual size — a
    /// picture smaller than the window would otherwise have no room to zoom at all.
    static func maximumScale(fittingScale: Double) -> Double {
        max(fittingScale * 8, 1)
    }
}

/// Floating point slack for "is this still the fitted scale".
let imageZoomEpsilon = 0.0001
