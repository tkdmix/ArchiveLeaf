#if os(macOS)
import SwiftUI

/// Takes the window title out of the bar where its pane cannot hold both the name and the controls.
///
/// Emptying the title is not enough: the slot is about 170 points wide and keeps that room whether
/// or not there is a word in it, which is what pushed a narrow pane's controls over the divider.
@available(macOS 15.0, *)
private struct RemovableTitle: ViewModifier {
    let hasRoom: Bool

    func body(content: Content) -> some View {
        content.toolbar(removing: hasRoom ? nil : .title)
    }
}

struct TitleShownWhenThereIsRoom: ViewModifier {
    let hasRoom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.modifier(RemovableTitle(hasRoom: hasRoom))
        } else {
            content
        }
    }
}
#endif
