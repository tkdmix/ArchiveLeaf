import Foundation
import XCTest
@testable import ArchiveLeaf

final class ArchiveBrowsingStateTests: XCTestCase {
    func testInitialStateShowsUnsortedWithoutFocusOrSelection() {
        let state = ArchiveBrowsingState()

        XCTAssertEqual(state.location, .unsorted)
        XCTAssertNil(state.focusedFileID)
        XCTAssertEqual(state.selectedItemIDs, [])
        XCTAssertFalse(state.isSelectingItems)
    }

    func testLocationsRepresentRootsAndFolderWithoutInvalidCombinations() {
        let folderID = UUID()

        XCTAssertEqual(ArchiveBrowsingLocation.folders, .folders)
        XCTAssertEqual(ArchiveBrowsingLocation.unsorted, .unsorted)
        XCTAssertEqual(ArchiveBrowsingLocation.folder(folderID), .folder(folderID))
        XCTAssertEqual(ArchiveBrowsingLocation.favorites, .favorites)
        XCTAssertEqual(ArchiveBrowsingLocation.tag(path: ""), .tag(path: ""))
        XCTAssertEqual(ArchiveBrowsingLocation.tag(path: "Work/ArchiveLeaf"), .tag(path: "Work/ArchiveLeaf"))
        XCTAssertEqual(ArchiveBrowsingLocation.trash, .trash)
    }

    func testShowingScopeAndTagLocationsClearsFocusAndSelectionMode() {
        let locations: [ArchiveBrowsingLocation] = [
            .folders,
            .favorites,
            .tag(path: ""),
            .tag(path: "Work/ArchiveLeaf"),
            .trash,
        ]

        for location in locations {
            var state = selectingState()
            state.show(location)

            XCTAssertEqual(state.location, location)
            assertNoFocusOrSelection(state)
        }
    }

    func testOpeningFolderAndShowingUnsortedAreLocationTransitions() {
        let folderID = UUID()
        var state = selectingState()

        state.openFolder(folderID)
        XCTAssertEqual(state.location, .folder(folderID))
        assertNoFocusOrSelection(state)

        state.beginSelecting()
        state.selectItem(UUID())
        state.showUnsorted()
        XCTAssertEqual(state.location, .unsorted)
        assertNoFocusOrSelection(state)
    }

    func testFocusingFileKeepsLocationAndClearsMultiSelection() {
        let id = UUID()
        var state = selectingState(location: .tag(path: "Reference"))

        state.focusFile(id)

        XCTAssertEqual(state.location, .tag(path: "Reference"))
        XCTAssertEqual(state.focusedFileID, id)
        XCTAssertEqual(state.selectedItemIDs, [])
        XCTAssertFalse(state.isSelectingItems)
    }

    func testBeginningSelectionClearsFocusAndPriorSelection() {
        var state = ArchiveBrowsingState()
        state.focusFile(UUID())

        state.beginSelecting()

        XCTAssertNil(state.focusedFileID)
        XCTAssertEqual(state.selectedItemIDs, [])
        XCTAssertTrue(state.isSelectingItems)
    }

    func testSelectionChangesOnlyInSelectionMode() {
        let first = UUID()
        let second = UUID()
        var state = ArchiveBrowsingState()

        state.selectItem(first)
        state.toggleItemSelection(first)
        XCTAssertEqual(state.selectedItemIDs, [])

        state.beginSelecting()
        state.selectItem(first)
        state.selectItem(first)
        state.toggleItemSelection(second)
        XCTAssertEqual(state.selectedItemIDs, [first, second])

        state.toggleItemSelection(first)
        XCTAssertEqual(state.selectedItemIDs, [second])
    }

    func testFinishAndClearSelectionHaveDistinctModeSemantics() {
        var state = selectingState()

        state.clearSelection()
        XCTAssertEqual(state.selectedItemIDs, [])
        XCTAssertTrue(state.isSelectingItems)

        state.selectItem(UUID())
        state.finishSelecting()
        assertNoFocusOrSelection(state)
    }

    func testReplacingListSelectionUsesTheSelectionModeOnlyWhenRowsAreSelected() {
        let first = UUID()
        let second = UUID()
        var state = ArchiveBrowsingState()
        state.focusFile(UUID())

        state.replaceSelectedItems([first, second])

        XCTAssertNil(state.focusedFileID)
        XCTAssertEqual(state.selectedItemIDs, [first, second])
        XCTAssertTrue(state.isSelectingItems)

        state.replaceSelectedItems([])

        assertNoFocusOrSelection(state)
    }

    func testReconcileRemovesOnlyStaleFocusAndSelectedItems() {
        let retained = UUID()
        let stale = UUID()
        var state = ArchiveBrowsingState()
        state.focusFile(stale)
        state.reconcile(availableItemIDs: [retained])
        XCTAssertNil(state.focusedFileID)

        state.beginSelecting()
        state.selectItem(retained)
        state.selectItem(stale)
        state.reconcile(availableItemIDs: [retained])

        XCTAssertEqual(state.selectedItemIDs, [retained])
        XCTAssertTrue(state.isSelectingItems)

        state.focusFile(retained)
        state.reconcile(availableItemIDs: [retained])
        XCTAssertEqual(state.focusedFileID, retained)
    }

    func testTransitionsAreIdempotentWhereRepeatedActionHasNoNewEffect() {
        let location = ArchiveBrowsingLocation.tag(path: "")
        let id = UUID()
        var state = ArchiveBrowsingState()

        state.show(location)
        let shown = state
        state.show(location)
        XCTAssertEqual(state, shown)

        state.beginSelecting()
        let selecting = state
        state.beginSelecting()
        XCTAssertEqual(state, selecting)

        state.selectItem(id)
        let selected = state
        state.selectItem(id)
        XCTAssertEqual(state, selected)

        state.reconcile(availableItemIDs: [id])
        let reconciled = state
        state.reconcile(availableItemIDs: [id])
        XCTAssertEqual(state, reconciled)
    }


    /// A tab bar is the platform's own control and its tabs remember their depth. Leaving Folders
    /// for Tags and coming back returns to the folder that was open, not to the top of the tree.
    func testSwitchingSectionLeavesEachAreaWhereItWas() {
        let folderID = UUID()
        var state = ArchiveBrowsingState()
        state.openFolder(folderID)

        state.showSection(.tags)
        XCTAssertEqual(state.section, .tags)
        XCTAssertEqual(state.location, .tag(path: ""))

        state.show(.tag(path: "Work/ArchiveLeaf"))
        state.showSection(.folders)

        XCTAssertEqual(state.section, .folders)
        XCTAssertEqual(state.location, .folder(folderID))

        state.showSection(.tags)
        XCTAssertEqual(state.location, .tag(path: "Work/ArchiveLeaf"))
    }

    /// A location belongs to exactly one area, so choosing one from a sidebar moves the area too.
    func testShowingALocationMovesToTheAreaThatOwnsIt() {
        var state = ArchiveBrowsingState()

        state.show(.tag(path: "Reference"))
        XCTAssertEqual(state.section, .tags)

        state.show(.trash)
        XCTAssertEqual(state.section, .trash)

        state.show(.favorites)
        XCTAssertEqual(state.section, .favorites)

        state.openFolder(UUID())
        XCTAssertEqual(state.section, .folders)
    }

    /// An area never entered begins at its own root rather than at another area's place.
    func testUnvisitedAreasBeginAtTheirOwnRoot() {
        var state = ArchiveBrowsingState()

        XCTAssertEqual(state.location(in: .folders), .unsorted)
        XCTAssertEqual(state.location(in: .favorites), .favorites)
        XCTAssertEqual(state.location(in: .tags), .tag(path: ""))
        XCTAssertEqual(state.location(in: .trash), .trash)

        state.showSection(.trash)
        XCTAssertEqual(state.location, .trash)
    }

    /// A focused file is part of how deep an area is, so it is remembered per area — a compact
    /// layout shows it as the last screen of that tab's stack.
    func testFocusIsKeptPerAreaAndSelectionIsNot() {
        let inFolders = UUID()
        let inFavorites = UUID()
        var state = ArchiveBrowsingState()

        state.focusFile(inFolders)
        state.showSection(.favorites)
        XCTAssertNil(state.focusedFileID)

        state.focusFile(inFavorites)
        state.showSection(.folders)
        XCTAssertEqual(state.focusedFileID, inFolders)
        XCTAssertEqual(state.focusedFileID(in: .favorites), inFavorites)

        state.beginSelecting()
        state.selectItem(UUID())
        state.showSection(.tags)
        XCTAssertFalse(state.isSelectingItems)
        XCTAssertEqual(state.selectedItemIDs, [])
    }

    /// Popping a file's screen without leaving the list it was opened from.
    func testClearingFocusKeepsTheLocation() {
        let folderID = UUID()
        var state = ArchiveBrowsingState()
        state.openFolder(folderID)
        state.focusFile(UUID())

        state.clearFocusedFile()

        XCTAssertEqual(state.location, .folder(folderID))
        XCTAssertNil(state.focusedFileID)
    }

    func testShowingTheSameSectionTwiceHasNoNewEffect() {
        var state = ArchiveBrowsingState()
        state.openFolder(UUID())

        state.showSection(.tags)
        let shown = state
        state.showSection(.tags)

        XCTAssertEqual(state, shown)
    }


    /// Where the reader was is written down; what they had open or selected at that moment is not.
    func testOnlyThePlaceSurvivesBeingWrittenDownAndReadBack() throws {
        let folderID = UUID()
        var state = ArchiveBrowsingState()
        state.openFolder(folderID)
        state.showSection(.tags)
        state.show(.tag(path: "work"))
        state.focusFile(UUID())
        state.beginSelecting()
        state.selectItem(UUID())

        let restored = try JSONDecoder().decode(
            ArchiveBrowsingState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(restored.section, .tags)
        XCTAssertEqual(restored.location, .tag(path: "work"))
        XCTAssertEqual(restored.location(in: .folders), .folder(folderID))
        XCTAssertNil(restored.focusedFileID)
        XCTAssertEqual(restored.selectedItemIDs, [])
        XCTAssertFalse(restored.isSelectingItems)
    }

    /// A folder deleted on another device leaves this one remembering a name that stands for
    /// nothing. That area gives way to its own root; the others are left where they were.
    func testAPlaceThatNoLongerExistsGivesWayToItsOwnRoot() {
        let kept = UUID()
        let deleted = UUID()
        var state = ArchiveBrowsingState()
        state.openFolder(deleted)
        state.show(.tag(path: "gone"))

        state.reconcileLocations(existingFolderIDs: [kept], existingTagPaths: ["work"])

        XCTAssertEqual(state.location(in: .folders), .folders)
        XCTAssertEqual(state.location(in: .tags), .tag(path: ""))

        var stillThere = ArchiveBrowsingState()
        stillThere.openFolder(kept)
        stillThere.reconcileLocations(existingFolderIDs: [kept], existingTagPaths: [])
        XCTAssertEqual(stillThere.location, .folder(kept))
    }

    /// The store hands back a fresh state rather than failing when it has nothing to hand back.
    func testTheStoreReturnsAFreshStateWhenNothingWasWrittenOrItCannotBeRead() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        // Asked to remember explicitly: these tests run against the in-memory sample, where the
        // store deliberately remembers nothing.
        let store = ArchiveBrowsingStateStore(
            defaults: defaults,
            key: "test.browsingState",
            remembers: true
        )

        XCTAssertEqual(store.load(), ArchiveBrowsingState())

        var state = ArchiveBrowsingState()
        let folderID = UUID()
        state.openFolder(folderID)
        store.save(state)
        XCTAssertEqual(store.load().location, .folder(folderID))

        defaults.set(Data("not a browsing state".utf8), forKey: "test.browsingState")
        XCTAssertEqual(store.load(), ArchiveBrowsingState())
    }

    /// The sample archive is built afresh at every launch, so there is no previous session in it to
    /// return to — and a test that inherited where the last one finished would repeat nothing.
    func testTheStoreRemembersNothingAgainstTheSampleArchive() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = ArchiveBrowsingStateStore(
            defaults: defaults,
            key: "test.browsingState",
            remembers: false
        )
        var state = ArchiveBrowsingState()
        state.openFolder(UUID())

        store.save(state)

        XCTAssertEqual(store.load(), ArchiveBrowsingState())
    }

    // MARK: Selection belongs to one area

    /// Every area's list is alive at once behind the tabs, and one that is no longer on top can
    /// still be told by the framework that it has gone away — after the reader has already begun
    /// choosing somewhere else. That late word used to end the new selection, and Select appeared
    /// to do nothing. It is now unaddressed: only the area that is choosing can stop choosing.
    func testAnotherAreaCannotEndTheSelectionBeingMade() {
        var state = ArchiveBrowsingState()
        state.show(.favorites)
        state.beginSelecting()
        let chosen = UUID()
        state.selectItem(chosen)

        state.setSelecting(false, in: .folders)
        state.setSelecting(false, in: .trash)

        XCTAssertTrue(state.isSelectingItems)
        XCTAssertEqual(state.selectedItemIDs, [chosen])
    }

    func testTheAreaBeingWorkedInEndsItsOwnSelection() {
        var state = ArchiveBrowsingState()
        state.show(.favorites)
        state.setSelecting(true, in: .favorites)
        XCTAssertTrue(state.isSelectingItems)

        state.setSelecting(false, in: .favorites)

        XCTAssertFalse(state.isSelectingItems)
        XCTAssertEqual(state.selectedItemIDs, [])
    }

    /// A list behind another tab reports its own empty selection as it is built. That is not the
    /// reader unticking anything.
    func testAnotherAreasReportedSelectionIsNotThisOne() {
        var state = ArchiveBrowsingState()
        state.show(.favorites)
        state.beginSelecting()
        let chosen = UUID()
        state.updateSelectedItems([chosen], in: .favorites)

        state.updateSelectedItems([], in: .folders)

        XCTAssertEqual(state.selectedItemIDs, [chosen])
        XCTAssertTrue(state.isSelectingItems)
    }

    /// An area that is not on screen cannot start choosing either.
    func testOnlyTheAreaOnScreenCanBeginChoosing() {
        var state = ArchiveBrowsingState()
        state.show(.favorites)

        state.setSelecting(true, in: .folders)

        XCTAssertFalse(state.isSelectingItems)
        XCTAssertFalse(state.isSelectingItems(in: .folders))
    }

    /// Leaving an area still ends what was being chosen there, which is what a tab does.
    func testLeavingTheAreaEndsItsSelection() {
        var state = ArchiveBrowsingState()
        state.show(.favorites)
        state.beginSelecting()
        state.selectItem(UUID())

        state.showSection(.folders)

        XCTAssertFalse(state.isSelectingItems)
        XCTAssertFalse(state.isSelectingItems(in: .favorites))
        XCTAssertEqual(state.selectedItemIDs, [])
    }

    private func selectingState(
        location: ArchiveBrowsingLocation = .unsorted
    ) -> ArchiveBrowsingState {
        var state = ArchiveBrowsingState()
        state.show(location)
        state.beginSelecting()
        state.selectItem(UUID())
        return state
    }

    private func assertNoFocusOrSelection(
        _ state: ArchiveBrowsingState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(state.focusedFileID, file: file, line: line)
        XCTAssertEqual(state.selectedItemIDs, [], file: file, line: line)
        XCTAssertFalse(state.isSelectingItems, file: file, line: line)
    }
}
