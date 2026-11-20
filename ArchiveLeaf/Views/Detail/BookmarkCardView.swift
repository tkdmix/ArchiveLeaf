#if !os(macOS)
import SwiftUI

/// What a bookmark looks like when its page is not on screen.
///
/// A bookmark is its address and nothing else, so on the Mac the pane simply shows the page and
/// there is no card at all. iOS shows the page full screen instead, which means closing it lands
/// somewhere — and on an iPad that somewhere is a pane standing beside the list, which cannot be
/// blank while a row is still selected. This is that landing place, and the way back in.
struct BookmarkCardView: View {
    let url: URL
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            // The host first and the whole address under it, at the size each deserves: the site is
            // what a reader recognises, and the rest is what they occasionally need to read.
            Text(verbatim: url.host() ?? url.absoluteString)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(verbatim: url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Open Page", systemImage: "safari", action: onOpen)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
