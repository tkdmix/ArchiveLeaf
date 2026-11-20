import SwiftUI

#if !os(macOS)
/// A pane's name, written where the pane's content is.
///
/// Not in the navigation bar. A large title in the bar is not a title that stays put: it shrinks as
/// the reader scrolls and slides up into the row of controls, so the top of the screen means one
/// thing at rest and another thing a moment later, and the name ends up sitting among buttons it
/// has nothing to do with. Here the bar holds controls and only controls, and the name belongs to
/// the list it names — it scrolls with it, as any other heading does.
///
/// Written once, for all four panes. The folder pane was given this first and the other three kept
/// the shrinking title for a while, which is what a per-screen copy of an idea always costs.
///
/// Private on purpose: it is reachable only through `ArchiveTitledSection`, so a title cannot be
/// dropped in among rows even by someone who has not read why it must not be.
private struct ArchiveContentTitle: View {
    private let title: Text

    init(_ title: Text) {
        self.title = title
    }

    init(_ key: LocalizedStringResource) {
        self.init(Text(key))
    }

    /// A name the reader gave something, which is not translated and not restyled by a section.
    init(verbatim name: String) {
        self.init(Text(verbatim: name))
    }

    var body: some View {
        title
            .font(.largeTitle.bold())
            .textCase(nil)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            // Named, so that a test asking "where am I" has something to ask that is not the
            // wording. The bar's name used to answer it, and moving the name in here turned three
            // navigation tests red at once. Only one pane carries a content title — it is shown
            // where a pane is the whole screen — so the name is unambiguous on screen.
            .accessibilityIdentifier("content-title")
    }
}

/// A pane's rows, with the pane's name above them — as a header, never as a row.
///
/// A title and a row are different kinds of thing, and a list draws its group's rounded corners
/// around its first and last **rows**. Put the title in among them and the corner belongs to the
/// title: the first real row comes out square at the top, whether or not the title row was given a
/// clear background. It has been written that way twice now, in the folder pane and again in
/// Favorites, Tags and the Trash — so the two are not offered separately any more. Ask for the
/// rows; the title arrives above them, outside the group, or not at all.
struct ArchiveTitledSection<Content: View>: View {
    private let title: Text
    private let isShowingContentTitle: Bool
    private let content: Content

    init(
        _ title: Text,
        isShowingContentTitle: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isShowingContentTitle = isShowingContentTitle
        self.content = content()
    }

    init(
        _ key: LocalizedStringResource,
        isShowingContentTitle: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.init(Text(key), isShowingContentTitle: isShowingContentTitle, content: content)
    }

    var body: some View {
        if isShowingContentTitle {
            Section {
                content
            } header: {
                ArchiveContentTitle(title)
            }
        } else {
            Section {
                content
            }
        }
    }
}

extension View {
    /// Leaves the navigation bar to the controls, for a pane that carries its own title.
    ///
    /// Four things, because leaving any of them out brings the bar's title back in some form: the
    /// name given to the bar only where the content does not carry it, nothing to draw where it
    /// does, inline so nothing can grow into a large title, and no top margin above the content,
    /// which the bar would otherwise reserve for the title it is not drawing.
    ///
    /// `barTitle` is what the bar says when the content is not saying it — which is where this pane
    /// is a column beside others rather than the whole screen.
    func archiveContentTitleChrome(
        _ isShowingContentTitle: Bool,
        barTitle: Text
    ) -> some View {
        modifier(
            ArchiveContentTitleChrome(
                isShowingContentTitle: isShowingContentTitle,
                barTitle: barTitle
            )
        )
    }
}

private struct ArchiveContentTitleChrome: ViewModifier {
    let isShowingContentTitle: Bool
    let barTitle: Text

    @ViewBuilder
    func body(content: Content) -> some View {
        if isShowingContentTitle {
            content
                .navigationTitle(Text(verbatim: ""))
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                // Shown even where there is nothing in it. Asking for the bar itself, rather than
                // putting something invisible inside it: an item takes a slot, and a slot takes the
                // spacing beside it — which pushed the real controls apart in the three panes that
                // have them.
                .toolbar(.visible, for: .navigationBar)
        } else {
            content.navigationTitle(barTitle)
        }
    }

}
#endif
