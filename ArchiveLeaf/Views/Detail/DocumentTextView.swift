import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A long document, drawn by the platform's text view.
///
/// SwiftUI's `Text` has no notion of a viewport: it typesets the whole document on every draw, and
/// a profile of a 10 KB Japanese note showed the cost was CoreText laying the lot out again, most
/// of it running the font fallback for the Japanese runs. TextKit 2 lays out what is on screen and
/// nothing else, which is why Apple rebuilt it that way — and why no document app anywhere hands a
/// whole file to a single text object.
///
/// Read-only and selectable: this is an archive, and the point of a text view here is that a
/// selection can run the length of the document.
///
/// A link in the document is activated through the text view's own delegate, which is where both
/// AppKit and UIKit put it. Nothing else here is platform-specific: the delegate hands the URL
/// straight back out, and what to do with it — open it in the app, or ask before leaving — stays
/// with the one caller that already decides that for every other link.
///
/// Why this exists at all: SwiftUI's `Text` routes its links through the `openURL` environment for
/// free, and this view does not, because it is not `Text`. Moving to TextKit 2 was for a long
/// document's typesetting cost, and it silently took link handling with it — a document's link
/// opened the system browser rather than the reader's archive. Maintained on both platforms until
/// `Text` can typeset a long document without laying the whole of it out on every draw; at that
/// point this view and its two delegates go together.
struct DocumentTextView {
    let text: AttributedString
    /// Where a link in the document goes.
    var onOpenLink: (URL) -> Void = { _ in }
}

#if os(macOS)
extension DocumentTextView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(onOpenLink: onOpenLink) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenLink: (URL) -> Void

        init(onOpenLink: @escaping (URL) -> Void) {
            self.onOpenLink = onOpenLink
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = link as? URL ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            onOpenLink(url)
            // Handled here: returning false hands the link to the system browser.
            return true
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        // Named rather than left to the default: SwiftUI's Text carried `.primary`, and without an
        // equivalent the body came out dim against a dark window.
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onOpenLink = onOpenLink
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let updated = NSAttributedString(text)
        guard textView.attributedString() != updated else { return }
        textView.textStorage?.setAttributedString(updated)
    }
}
#else
extension DocumentTextView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(onOpenLink: onOpenLink) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenLink: (URL) -> Void

        init(onOpenLink: @escaping (URL) -> Void) {
            self.onOpenLink = onOpenLink
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            onOpenLink(url)
            // No action of the system's own: its default here is to leave for the system browser.
            return nil
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        // Named rather than left to the default: SwiftUI's Text carried `.primary`, and without an
        // equivalent the body came out dim against a dark screen.
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onOpenLink = onOpenLink
        let updated = NSAttributedString(text)
        guard textView.attributedText != updated else { return }
        textView.attributedText = updated
    }
}
#endif
