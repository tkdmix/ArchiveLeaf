#if !os(macOS)
import SafariServices
import SwiftUI

/// The system's own in-app browser, shown whole.
///
/// ArchiveLeaf does not build a browser on iOS. `SFSafariViewController` arrives already holding
/// what a reader expects a page to have: the sessions Safari is already signed in to, Reader,
/// AutoFill, and the content blockers they installed. None of that can be reproduced by a web view
/// the app drives itself, and reproducing the rest — a bar, history, an address — would only be
/// spending code to arrive somewhere worse.
///
/// The price is that the app cannot see inside. There is no navigation policy to apply, no error to
/// classify, and no chrome to arrange; Safari answers for all three. The one thing kept on this side
/// is which addresses are handed over at all, which `ArchiveURLHandler` decides before this view is
/// ever asked for.
///
/// It is shown full screen rather than inside a pane, on the phone and on the iPad alike. Apple
/// asks that it be presented unmodified and unobscured, and an iPad pane would be both.
extension View {
    /// Presents `page` in the system browser, clearing it when the reader closes it and telling
    /// `onClose` that they did — which is how the screen behind decides whether it is still worth
    /// showing.
    func safariBrowser(page: Binding<URL?>, onClose: @escaping () -> Void) -> some View {
        modifier(SafariBrowserPresentation(page: page, onClose: onClose))
    }
}

private struct SafariBrowserPresentation: ViewModifier {
    @Binding var page: URL?
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(
            item: Binding(
                get: { page.map(BrowsedPage.init) },
                set: { page = $0?.url }
            )
        ) { page in
            SafariBrowser(url: page.url) {
                self.page = nil
                onClose()
            }
            .ignoresSafeArea()
        }
    }
}

/// A page as something a presentation can be keyed on. Identified by its address, so that opening a
/// different one while the browser is up replaces the page rather than leaving the first in place.
private struct BrowsedPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariBrowser: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        // The close cross, not "Done": nothing was being done here. The page was being looked at,
        // and this puts it away.
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    /// Nothing to update. A `SFSafariViewController` is given its address once and cannot be sent to
    /// another; a new address arrives as a new presentation, which `BrowsedPage`'s identity forces.
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}
#endif
