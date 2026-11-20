import SwiftUI

/// What every document carries, kept in the bar when there is none.
///
/// A section of the window's toolbar exists only where both sides of a split's divider have
/// something to show. With the document pane empty there is no section over it, and the controls
/// of the pane beside it slide off their own pane to the window's edge — the same controls in two
/// places depending on whether anything is selected. Dimmed rather than absent is how a Mac says
/// "not now": Mail keeps Reply and Forward in the bar with no message open.
///
/// Only these three. Zooming belongs to a picture and finding to a document, so those come and go
/// with what is open.
/// Collapses the same way a document's own controls do. An empty pane is no reason to hold the
/// window open any more than a full one is.
private struct DocumentControlsPlaceholder: ViewModifier {
    let isShown: Bool
    #if os(macOS)
    @State private var paneWidth: CGFloat = 0
    #endif

    #if os(macOS)
    /// Match a document's initial layout while its selection changes, then compact genuinely
    /// narrow macOS panes. Mobile controls stay independent and leave overflow to the system.
    private var hasRoomForEveryControl: Bool {
        guard paneWidth > 0 else { return true }
        return paneWidth >= 300
    }
    #endif

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            .measuringPaneWidth(into: $paneWidth)
            #endif
            .toolbar {
                #if os(macOS)
                if isShown, hasRoomForEveryControl {
                    ToolbarItem {
                        Button("Add to Favorites", systemImage: "star") {}
                            .disabled(true)
                    }
                    ToolbarItem {
                        Button("Share", systemImage: "square.and.arrow.up") {}
                            .disabled(true)
                    }
                    ToolbarItem {
                        Button("Info", systemImage: "info.circle") {}
                            .disabled(true)
                    }
                } else if isShown {
                    ToolbarItem {
                        Button("Add to Favorites", systemImage: "star") {}
                            .disabled(true)
                    }
                    ToolbarItem {
                        Button("More", systemImage: "ellipsis") {}
                            .disabled(true)
                    }
                }
                #else
                if isShown {
                    ToolbarItem {
                        Button("Add to Favorites", systemImage: "star") {}
                            .disabled(true)
                    }
                    ToolbarItem {
                        Button("Share", systemImage: "square.and.arrow.up") {}
                            .disabled(true)
                    }
                    ToolbarItem {
                        Button("Info", systemImage: "info.circle") {}
                            .disabled(true)
                    }
                }
                #endif
            }
    }
}

extension View {
    func documentControlsPlaceholder(isShown: Bool) -> some View {
        modifier(DocumentControlsPlaceholder(isShown: isShown))
    }
}
