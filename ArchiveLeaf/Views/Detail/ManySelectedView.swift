import SwiftUI

/// What the document pane says when several things are chosen at once.
///
/// There is no one document to show, and guessing at one — the last clicked, say — would put a
/// file on screen that the next command is not about. The count is what the reader needs to see to
/// know what they are about to move or throw away.
struct ManySelectedView: View {
    let count: Int
    @State private var paneWidth: CGFloat = 0

    var body: some View {
        PaneNotice(
            "\(count) Items Selected",
            systemImage: "square.on.square",
            width: paneWidth
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .measuringPaneWidth(into: $paneWidth)
        .navigationTitle("\(count) Items Selected")
        .documentControlsPlaceholder(isShown: true)
    }
}
