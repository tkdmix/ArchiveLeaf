import SwiftUI

#if !os(macOS)
/// Choosing several rows at once, and the bar of actions that comes with it.
///
/// Written once because a list is a list: the folder list had it and Favorites, a tag's files and
/// the Trash did not, which meant the same file could be picked in one place and not in another.
/// A screen supplies its own list — it knows which rows it has — and its own actions; everything
/// around them, the Select and Done control, the bar standing in for the tabs, and the decision of
/// whether the actions are wide enough to say their words, is here.
extension View {
    func archiveSelectionBar<Actions: ToolbarContent>(
        isSelecting: Binding<Bool>,
        canSelect: Bool,
        @ToolbarContentBuilder actions: @escaping (Bool) -> Actions
    ) -> some View {
        modifier(ArchiveSelectionBar(isSelecting: isSelecting, canSelect: canSelect, actions: actions))
    }
}

private struct ArchiveSelectionBar<Actions: ToolbarContent>: ViewModifier {
    @Binding var isSelecting: Bool
    /// Whether there is anything here to choose. An empty list offers no Select.
    let canSelect: Bool
    /// Given whether there is room for words rather than symbols alone.
    let actions: (Bool) -> Actions
    /// How large the reader has asked their text to be. At the accessibility sizes four words do
    /// not fit across a phone, and the last of them was cut off at the edge.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Whether this is a window with room to spare. An iPad has room for the words at any text
    /// size; a phone does not.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Words where they fit and symbols where they do not.
    ///
    /// The reader's text size is theirs, not ours to cap: at the accessibility sizes the four words
    /// ran off the edge of a phone, and the answer is to say the same thing in less room rather
    /// than to shrink what they asked to enlarge. What is read aloud stays the word either way.
    private var showsWords: Bool {
        horizontalSizeClass == .regular || dynamicTypeSize < .xxLarge
    }

    func body(content: Content) -> some View {
        content
            // The tab bar stands down while a selection is being made, and the actions for that
            // selection take its place. That is what Files and Photos do, and without it the bar of
            // actions was drawn underneath the tabs on a phone — present, and invisible.
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .toolbar {
                if isSelecting {
                    actions(showsWords)
                }
                // Selection is another independent trailing command. The system decides its
                // normal toolbar spacing and, when necessary, which trailing item overflows.
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Done") { isSelecting = false }
                    } else {
                        // The checkmark-in-a-circle is the platform's compact affordance for
                        // entering multi-selection. Keep the title for VoiceOver and the button's
                        // accessibility action; only its visible label is icon-only.
                        Button("Select", systemImage: "checkmark.circle") { isSelecting = true }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Select")
                            .disabled(!canSelect)
                    }
                }
            }
    }
}

/// What can be done to what has been chosen in the archive, in the order of the tabs: place, star,
/// tag, trash. They are the same four ideas, used here as verbs rather than as destinations, so a
/// finger that has learned where one of them sits finds it in the same place. The two bars are
/// never on screen at once — the tab bar stands down while this one is up.
///
/// Words, not icons. The selection bar in Files is written out, and four unlabelled symbols that
/// also name the four tabs would ask the reader to remember which bar they are looking at. A
/// toolbar draws its buttons its own way and ignores `labelStyle` on them — measured: with an icon
/// given, each button came out 38 to 50 points wide, which holds a symbol and no word. So no
/// symbols are given where the words are shown.
struct ArchiveSelectionActions: ToolbarContent {
    let selection: ArchiveItemSelection
    let viewModel: ArchiveViewModel
    let showsWords: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            moveButton
            Spacer()
            favoriteButton
            Spacer()
            tagMenu
            Spacer()
            trashButton
            Spacer()
        }
    }

    private var moveButton: some View {
        Button("Move", systemImage: "folder") {
            viewModel.beginMoving(selection.items)
        }
        .modifier(SelectionBarLabel(showsWords: showsWords))
        .disabled(!selection.canMove || viewModel.isOfflineMode)
    }

    private var trashButton: some View {
        Button("Trash", systemImage: "trash", role: .destructive) {
            viewModel.itemsPendingTrash = selection.items
        }
        .modifier(SelectionBarLabel(showsWords: showsWords))
        .disabled(!selection.canTrash || viewModel.isOfflineMode)
    }

    /// A menu that cannot be used is drawn as a button that cannot be pressed.
    ///
    /// `disabled` on a `Menu` stops it opening but leaves it looking live — measured: with a folder
    /// among the chosen items the tag control stayed blue while the star beside it had gone grey.
    /// A control that says it can be used and then does nothing is worse than one that admits it.
    @ViewBuilder
    private var tagMenu: some View {
        if selection.canTag && !viewModel.isOfflineMode {
            TagAssignmentMenu(files: selection.files, viewModel: viewModel)
                .modifier(SelectionBarLabel(showsWords: showsWords))
        } else {
            Button("Tags", systemImage: "tag") {}
                .modifier(SelectionBarLabel(showsWords: showsWords))
                .disabled(true)
        }
    }

    /// Adding wins where the choice is mixed: the reader who picked ten and pressed the star meant
    /// to mark them, not to unmark the two that were already marked.
    private var favoriteButton: some View {
        let files = selection.files
        let isAdding = files.isEmpty || files.contains { !$0.isFavorite }
        // Written out, because the bar is words: which way it will go has to be in the word.
        return Button(
            isAdding ? "Favorite" : "Unfavorite",
            systemImage: isAdding ? "star" : "star.slash"
        ) {
            // The whole selection in one write. A loop of single saves is a round trip per file,
            // and it showed: the stars filled in one at a time, half a second apart.
            Task { await viewModel.setFavorite(isAdding, on: files.map(\.id)) }
        }
        .modifier(SelectionBarLabel(showsWords: showsWords))
        .disabled(!selection.canFavorite || viewModel.isOfflineMode)
    }
}

/// What can be done to what has been chosen in the Trash: back where it came from, or gone.
///
/// Two verbs rather than four, because the other four belong to the archive — a discarded file has
/// no place to be moved to and no tag worth changing until it is back. Restore comes first: it is
/// the one that can be taken back, and the one that cannot is at the far end, where the archive's
/// own Trash button sits.
struct ArchiveTrashSelectionActions: ToolbarContent {
    let selection: ArchiveItemSelection
    let isOffline: Bool
    let showsWords: Bool
    let restore: ([ArchiveItem]) -> Void
    let deletePermanently: ([ArchiveItem]) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            Button("Restore", systemImage: "arrow.uturn.backward") {
                restore(selection.items)
            }
            .modifier(SelectionBarLabel(showsWords: showsWords))
            .disabled(!selection.canRestore || isOffline)
            Spacer()
            Button("Delete", systemImage: "xmark.bin", role: .destructive) {
                deletePermanently(selection.items)
            }
            .modifier(SelectionBarLabel(showsWords: showsWords))
            .disabled(!selection.canDeletePermanently || isOffline)
            Spacer()
        }
    }
}

/// A selection-bar control says its word where the words fit, and shows its symbol where they do
/// not. Written as a modifier because the two label styles are different types.
struct SelectionBarLabel: ViewModifier {
    let showsWords: Bool

    func body(content: Content) -> some View {
        if showsWords {
            content.labelStyle(.titleOnly)
        } else {
            content.labelStyle(.iconOnly)
        }
    }
}
#endif
