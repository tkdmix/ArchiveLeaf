import SwiftUI

/// Reports how wide the pane is, so its controls can decide how much of themselves to show.
///
/// The pane's size is the reader's to set. What sits above it gives way — the controls that do not
/// fit collapse behind one button rather than forcing the pane wider.
struct PaneWidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { _, newWidth in width = newWidth }
        }
    }
}

extension View {
    func measuringPaneWidth(into width: Binding<CGFloat>) -> some View {
        background { PaneWidthReader(width: width) }
    }
}
