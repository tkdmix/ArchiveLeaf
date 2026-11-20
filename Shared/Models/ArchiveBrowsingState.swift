import Foundation

/// One place a person can browse in the archive.
///
/// The folder heading is deliberately distinct from the unsorted-file list: the former is a
/// sidebar source, while the latter is the root folder's actual contents. A tag path may be
/// empty, which addresses the Tags heading itself.
enum ArchiveBrowsingLocation: Hashable, Sendable, Codable {
    case folders
    case unsorted
    case folder(UUID)
    case favorites
    case tag(path: String)
    case trash

    /// The primary area a location belongs to. Every location belongs to exactly one, which is
    /// what lets a compact tab and a regular-width sidebar row address the same state.
    var section: ArchivePrimarySection {
        switch self {
        case .folders, .unsorted, .folder: .folders
        case .favorites: .favorites
        case .tag: .tags
        case .trash: .trash
        }
    }

    /// Where an area begins, before anything has been opened inside it.
    static func root(of section: ArchivePrimarySection) -> Self {
        switch section {
        case .folders: .folders
        case .favorites: .favorites
        case .tags: .tag(path: "")
        case .trash: .trash
        }
    }
}

/// The canonical, platform-independent state for archive browsing.
///
/// Its transitions preserve these invariants: focused and selected items are mutually exclusive,
/// and selected item IDs exist only while item selection mode is active. Views project this value;
/// they do not keep a second selection or navigation state in sync with it.
///
/// Each primary area keeps its own place, because a compact tab bar is the platform's own control
/// and its tabs each remember how deep they are — Files, Notes, and Settings all behave this way.
/// A single shared location would have made switching to Tags and back throw away where the reader
/// was in Folders. What matters for the invariant is not that there is one location, but that
/// every location lives in one value, owned in one place, written in one direction. Views still
/// hold none of it: on iPad the layout is replaced as the window's width changes, and anything a
/// view held would be rebuilt at its initial value.
struct ArchiveBrowsingState: Hashable, Sendable, Codable {
    /// One area's place: where it is, and which file it has open there.
    private struct Place: Hashable, Sendable, Codable {
        var location: ArchiveBrowsingLocation
        var focusedFileID: UUID?
    }

    /// Which area is on screen. On a compact width this is the chosen tab; at regular width it
    /// follows from whichever sidebar row was chosen.
    private(set) var section: ArchivePrimarySection
    private var places: [ArchivePrimarySection: Place]
    private(set) var selectedItemIDs: Set<UUID>
    /// Which area is choosing several items at once, if any.
    ///
    /// An area rather than a plain yes-or-no, because every area's list is alive at the same time
    /// behind the tabs, and a screen that is no longer on top can still be told by the framework
    /// that it has gone away — late, and after the reader has already started choosing somewhere
    /// else. With one shared flag that stale word ended a selection nobody had finished, and the
    /// Select control appeared to do nothing. Naming the area makes such a word unaddressed rather
    /// than obeyed: only the area that is choosing can stop choosing.
    private(set) var selectingSection: ArchivePrimarySection?

    /// Archive browsing starts at the root's unsorted-file list.
    init() {
        section = .folders
        places = [.folders: Place(location: .unsorted, focusedFileID: nil)]
        selectedItemIDs = []
        selectingSection = nil
    }

    /// Whether the area on screen is choosing several items at once.
    var isSelectingItems: Bool { selectingSection == section }

    /// Whether one area is choosing, asked by that area itself. A list behind another tab is not
    /// selecting just because the visible one is.
    func isSelectingItems(in section: ArchivePrimarySection) -> Bool {
        selectingSection == section
    }

    var location: ArchiveBrowsingLocation {
        place(for: section).location
    }

    var focusedFileID: UUID? {
        place(for: section).focusedFileID
    }

    /// Where an area was left, for a tab that is not the one on screen.
    func location(in section: ArchivePrimarySection) -> ArchiveBrowsingLocation {
        place(for: section).location
    }

    func focusedFileID(in section: ArchivePrimarySection) -> UUID? {
        place(for: section).focusedFileID
    }

    /// Changes the visible location and discards state that belongs to the previous list.
    ///
    /// A location carries its own area, so choosing a tag from a sidebar moves to the tag area as
    /// well as to that tag.
    mutating func show(_ location: ArchiveBrowsingLocation) {
        section = location.section
        places[section] = Place(location: location, focusedFileID: nil)
        selectedItemIDs = []
        selectingSection = nil
    }

    /// Moves to another area, leaving it where it was last left.
    ///
    /// This is what a tab does. It is not `show`: returning to Folders after a look at Tags returns
    /// to the folder that was open, not to the top of the tree.
    mutating func showSection(_ section: ArchivePrimarySection) {
        self.section = section
        selectedItemIDs = []
        selectingSection = nil
    }

    mutating func openFolder(_ id: UUID) {
        show(.folder(id))
    }

    mutating func showUnsorted() {
        show(.unsorted)
    }

    /// Focuses one file without changing the current location.
    mutating func focusFile(_ id: UUID) {
        setFocusedFileID(id)
        selectedItemIDs = []
        selectingSection = nil
    }

    /// Lets go of the focused file without changing the current location. A compact layout pops
    /// the file's screen this way.
    mutating func clearFocusedFile() {
        setFocusedFileID(nil)
    }

    /// Lets go of every focused file the predicate names, in every area at once rather than only
    /// the area on screen — the others are restored too, and would push the same screen the moment
    /// their tab was chosen.
    ///
    /// A compact layout uses this at launch to drop what it has nowhere to show. Its screens are
    /// one stack, so a file whose whole content is a page it is not opening would stand there as a
    /// screen about a page: the reader is better returned to the list they were in.
    mutating func clearFocusedFiles(where shouldClear: (UUID) -> Bool) {
        for (section, place) in places {
            guard let id = place.focusedFileID, shouldClear(id) else { continue }
            places[section]?.focusedFileID = nil
        }
    }

    /// Enters multi-item selection, replacing any focused file or prior selection.
    mutating func beginSelecting() {
        setFocusedFileID(nil)
        selectedItemIDs = []
        selectingSection = section
    }

    /// Starts or stops choosing on behalf of one area.
    ///
    /// A stop is obeyed only from the area that is actually choosing, and a start only from the
    /// area on screen. That is the whole of the fix for a Select control that stopped answering:
    /// the screens are all alive at once, so their words have to say who is speaking.
    mutating func setSelecting(_ isSelecting: Bool, in section: ArchivePrimarySection) {
        if isSelecting {
            guard section == self.section else { return }
            beginSelecting()
        } else {
            guard selectingSection == section else { return }
            finishSelecting()
        }
    }

    /// Adds or removes an item from the multi-item selection when selection mode is active.
    mutating func toggleItemSelection(_ id: UUID) {
        guard isSelectingItems else { return }

        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    /// Adds an item to the multi-item selection when selection mode is active.
    mutating func selectItem(_ id: UUID) {
        guard isSelectingItems else { return }
        selectedItemIDs.insert(id)
    }

    /// Adopts a list control's complete selection.
    ///
    /// SwiftUI tables report an empty set when their last row is deselected. That means there is
    /// no active item-selection operation left to preserve, so an empty replacement also leaves
    /// selection mode. A nonempty replacement always takes precedence over a focused file.
    mutating func replaceSelectedItems(_ ids: Set<UUID>) {
        selectedItemIDs = ids
        setFocusedFileID(nil)
        selectingSection = ids.isEmpty ? nil : section
    }

    /// Takes a list control's complete selection while an explicit selection mode is running.
    ///
    /// Unlike `replaceSelectedItems`, emptying it does not end the mode. On iOS the reader enters
    /// selection deliberately and leaves it by pressing Done; unticking the last row is them
    /// changing their mind about that row, not about selecting. The other transition exists for the
    /// Mac's table, where the selection is the interaction and there is nothing to leave.
    mutating func updateSelectedItems(_ ids: Set<UUID>) {
        guard isSelectingItems else {
            replaceSelectedItems(ids)
            return
        }
        selectedItemIDs = ids
        setFocusedFileID(nil)
    }

    /// The same, from a list that says which area it is. A list behind another tab reports its own
    /// empty selection as it is built, and that word is not about the area being worked in.
    mutating func updateSelectedItems(_ ids: Set<UUID>, in section: ArchivePrimarySection) {
        guard selectingSection == section else { return }
        selectedItemIDs = ids
        setFocusedFileID(nil)
    }

    /// Leaves multi-item selection and clears every selected item.
    mutating func finishSelecting() {
        selectedItemIDs = []
        selectingSection = nil
    }

    /// Retains selection mode while clearing its current selection.
    mutating func clearSelection() {
        selectedItemIDs = []
    }

    /// Discards focused or selected IDs that no longer exist in the presented items.
    ///
    /// Only the area on screen is reconciled, because only its items were presented. An area left
    /// behind is reconciled when the reader returns to it and its list is presented again.
    mutating func reconcile(availableItemIDs: Set<UUID>) {
        if let focusedFileID, !availableItemIDs.contains(focusedFileID) {
            setFocusedFileID(nil)
        }
        selectedItemIDs.formIntersection(availableItemIDs)
    }

    /// Puts every remembered place back inside the archive that is actually there.
    ///
    /// Somewhere the reader was can be deleted on another device, and this one comes back to a
    /// name that no longer stands for anything. Such an area returns to its own root — which is
    /// also what happens when the other device's own record of where it was is the one that is
    /// right. Areas that are still valid are left exactly where they were.
    mutating func reconcileLocations(
        existingFolderIDs: Set<UUID>,
        existingTagPaths: Set<String>
    ) {
        for (section, place) in places {
            switch place.location {
            case .folder(let id) where !existingFolderIDs.contains(id):
                places[section] = Place(location: .root(of: section), focusedFileID: nil)
            case .tag(let path) where !path.isEmpty && !existingTagPaths.contains(path):
                places[section] = Place(location: .root(of: section), focusedFileID: nil)
            default:
                continue
            }
            if section == self.section {
                selectedItemIDs = []
                selectingSection = nil
            }
        }
    }

    // MARK: Written down between launches

    /// Only where the reader was. What is focused, what is selected, and whether a selection is
    /// being made belong to the moment rather than to the archive, so coming back begins clean.
    private enum CodingKeys: String, CodingKey {
        case section
        case places
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        section = try container.decode(ArchivePrimarySection.self, forKey: .section)
        places = try container.decode([ArchivePrimarySection: Place].self, forKey: .places)
        selectedItemIDs = []
        selectingSection = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(places, forKey: .places)
    }

    private func place(for section: ArchivePrimarySection) -> Place {
        places[section] ?? Place(
            location: .root(of: section),
            focusedFileID: nil
        )
    }

    private mutating func setFocusedFileID(_ id: UUID?) {
        var place = place(for: section)
        guard place.focusedFileID != id else { return }
        place.focusedFileID = id
        places[section] = place
    }
}
