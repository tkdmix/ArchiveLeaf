import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Handing an address to whatever the system opens it with. Kept apart from any one browser view
/// because every platform reaches for it: the Mac from its own browser pane, iOS from the
/// confirmation an unsupported scheme puts up.
@MainActor
func openOutsideArchiveLeaf(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}
