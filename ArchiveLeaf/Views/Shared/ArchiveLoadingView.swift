import SwiftUI

/// Waiting, in the middle of whatever is waiting.
///
/// The words name what is being read only where that is the whole archive — the app opening, a
/// window's folder pane. Reading one part of it, like the Trash, says only that it is loading:
/// the reader is already looking at the place the result will appear.
///
/// Pinned to the top-left corner, as it used to be, it read as a stray label rather than as the
/// state of the view it fills.
struct ArchiveLoadingView: View {
    var title: LocalizedStringKey = "Loading…"

    var body: some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
