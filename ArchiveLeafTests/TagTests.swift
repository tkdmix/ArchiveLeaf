import Foundation
import XCTest
@testable import ArchiveLeaf

@MainActor
final class TagTests: XCTestCase {
    private func makeViewModel(files: [ArchiveFile] = []) -> (ArchiveViewModel, InMemoryArchiveRepository) {
        let repository = InMemoryArchiveRepository(files: files)
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        return (viewModel, repository)
    }

    func testSlashSeparatedTagsBuildAPresentationTreeWithoutChangingStoredTags() {
        let ios = ArchiveTag(name: "Dev/Xcode/iOS")
        let mac = ArchiveTag(name: "Dev/Xcode/macOS")
        let shared = ArchiveFile(
            originalFileName: "shared.txt",
            tagIDs: [ios.id, mac.id],
            detectedFormat: .plainText
        )
        let macOnly = ArchiveFile(
            originalFileName: "mac.txt",
            tagIDs: [mac.id],
            detectedFormat: .plainText
        )

        let tree = TagPathNode.tree(tags: [mac, ios], files: [shared, macOnly])

        XCTAssertEqual(tree.map(\.name), ["Dev"])
        XCTAssertNil(tree[0].tag)
        XCTAssertEqual(
            tree[0].itemCount,
            1,
            "A row's number is the rows it opens onto: Dev opens onto Xcode alone"
        )
        let xcode = tree[0].children[0]
        XCTAssertEqual(xcode.name, "Xcode")
        XCTAssertNil(xcode.tag)
        XCTAssertEqual(xcode.children.map(\.name), ["iOS", "macOS"])
        XCTAssertEqual(xcode.children.map(\.tag?.name), ["Dev/Xcode/iOS", "Dev/Xcode/macOS"])
    }

    func testARealTagCanAlsoBeAnExpandableIntermediateNode() {
        let dev = ArchiveTag(name: "Dev")
        let ios = ArchiveTag(name: "Dev/iOS")

        let tree = TagPathNode.tree(tags: [ios, dev], files: [])

        XCTAssertEqual(tree[0].tag, dev)
        XCTAssertEqual(tree[0].children.first?.tag, ios)
    }

    func testTagPathRejectsEmptyLevels() {
        XCTAssertTrue(TagPathNode.isValidName("Dev/Xcode/iOS"))
        XCTAssertEqual(TagPathNode.normalizedName(" Dev / Xcode / iOS "), "Dev/Xcode/iOS")
        XCTAssertFalse(TagPathNode.isValidName("/Dev"))
        XCTAssertFalse(TagPathNode.isValidName("Dev/"))
        XCTAssertFalse(TagPathNode.isValidName("Dev//iOS"))
        XCTAssertFalse(TagPathNode.isValidName("Dev/ /iOS"))
    }

    func testMalformedLegacyTagRemainsVisibleAsOneRepairableNode() {
        let legacy = ArchiveTag(name: "Dev//iOS")

        let tree = TagPathNode.tree(tags: [legacy], files: [])

        XCTAssertEqual(tree.map(\.name), ["Dev//iOS"])
        XCTAssertEqual(tree.first?.tag, legacy)
    }

    func testCreatingATagWithAnExistingNameReturnsTheOneAlreadyThere() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()

        let first = await viewModel.createTag(named: "Recipes")
        let second = await viewModel.createTag(named: " recipes ")

        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(viewModel.tags.count, 1)
    }

    func testTaggingASelectionPutsTheTagOnEveryFileChosen() async {
        let one = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let two = ArchiveFile(originalFileName: "b.txt", detectedFormat: .plainText)
        let (viewModel, _) = makeViewModel(files: [one, two])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!

        await viewModel.setTag(tag.id, on: [one.id, two.id], isOn: true)

        XCTAssertEqual(Set(viewModel.files(taggedWithPath: TagPathNode.foldedKey(tag.name)).map(\.id)), [one.id, two.id])
    }

    func testUntaggingLeavesTheFilesListedEverywhereElse() async {
        let file = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let (viewModel, _) = makeViewModel(files: [file])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [file.id], isOn: true)

        await viewModel.setTag(tag.id, on: [file.id], isOn: false)

        XCTAssertTrue(viewModel.files(taggedWithPath: TagPathNode.foldedKey(tag.name)).isEmpty)
        XCTAssertEqual(viewModel.files.map(\.id), [file.id])
    }

    /// A tag id left on a file whose tag is gone would filter to nothing and show nowhere.
    func testDeletingATagTakesItOffTheFilesCarryingIt() async {
        let file = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let (viewModel, repository) = makeViewModel(files: [file])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [file.id], isOn: true)

        await viewModel.deleteTag(id: tag.id)

        XCTAssertTrue(viewModel.tags.isEmpty)
        XCTAssertEqual(viewModel.files.first?.tagIDs, [])
        let stored = await repository.fetchSnapshot()
        XCTAssertTrue(stored.tags.isEmpty)
        XCTAssertEqual(stored.files.first?.tagIDs, [])
    }

    /// The dialog clears what it was asking about as it closes, and it closes before the work its
    /// button started has run — so the work is given the id and never reads the dialog's state.
    /// `archiveConfirmation` is what makes that the only way to write it.
    func testDeletingATagAfterTheDialogHasClearedItself() async {
        let file = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let (viewModel, _) = makeViewModel(files: [file])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [file.id], isOn: true)
        viewModel.tagPendingDeletion = tag
        // As the dialog does on its way out, before the work has run.
        viewModel.tagPendingDeletion = nil

        await viewModel.deleteTag(id: tag.id)

        XCTAssertTrue(viewModel.tags.isEmpty)
        XCTAssertEqual(viewModel.files.first?.tagIDs, [])
    }

    /// CloudKit answers a query in whatever order it likes, and it came back differently each read.
    func testTagsAreListedInNameOrderWhateverOrderTheyWereRead() async {
        let recipes = ArchiveTag(name: "Recipes")
        let letters = ArchiveTag(name: "Letters")
        let aa = ArchiveTag(name: "Aa")
        // Carried by something, or they would not still be here to sort.
        let file = ArchiveFile(
            originalFileName: "a.txt",
            tagIDs: [recipes.id, letters.id, aa.id],
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(
            files: [file],
            tags: [recipes, letters, aa]
        )
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.tags.map(\.name), ["Aa", "Letters", "Recipes"])
    }

    /// A tag exists because a file carries it. Nothing carries it, nothing keeps it.
    func testATagGoesWhenTheLastFileLetsGoOfIt() async {
        let file = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let (viewModel, repository) = makeViewModel(files: [file])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [file.id], isOn: true)

        await viewModel.setTag(tag.id, on: [file.id], isOn: false)

        XCTAssertTrue(viewModel.tags.isEmpty)
        let stored = await repository.fetchSnapshot()
        XCTAssertTrue(stored.tags.isEmpty)
    }

    /// Something in the Trash is being considered, not gone. Dropping its tag would leave it
    /// naming nothing when it came back.
    func testATagStaysWhileItsOnlyFileIsInTheTrash() async {
        let file = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let other = ArchiveFile(originalFileName: "b.txt", detectedFormat: .plainText)
        let (viewModel, _) = makeViewModel(files: [file, other])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [file.id], isOn: true)

        await viewModel.moveToTrash([file.id])
        // Something else changing its tags is what sweeps up; the file in the Trash still counts.
        await viewModel.setTag(tag.id, on: [other.id], isOn: false)

        XCTAssertEqual(viewModel.tags.map(\.id), [tag.id])
    }

    /// Reading never deletes a tag, however empty it looks.
    ///
    /// This is the shape of a real loss. While one device imported bookmarks, another that merely
    /// came back on screen read an archive whose tag records had arrived and whose file records had
    /// not — CloudKit answers queries from an index that trails its own writes — and swept away
    /// every name it could not yet see a file for. The names were gone for both devices, and
    /// re-importing could not bring them back, because the bookmarks themselves were no longer new.
    func testReadingTheArchiveNeverDeletesATagNoFileAppearsToCarry() async {
        let carried = ArchiveTag(name: "Recipes")
        let notYetVisible = ArchiveTag(name: "GoodLinks/00daily")
        let file = ArchiveFile(
            originalFileName: "a.txt",
            tagIDs: [carried.id],
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(files: [file], tags: [carried, notYetVisible])
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        await viewModel.load()
        await viewModel.refresh()

        XCTAssertEqual(
            Set(viewModel.tags.map(\.id)),
            [carried.id, notYetVisible.id]
        )
        let stored = await repository.fetchSnapshot()
        XCTAssertEqual(Set(stored.tags.map(\.id)), [carried.id, notYetVisible.id])
    }

    /// And a tag another operation left alone stays, even where this device can see nothing
    /// carrying it. Only what the operation touched is considered.
    func testTakingATagOffOneFileLeavesUnrelatedNamesAlone() async {
        let removed = ArchiveTag(name: "Recipes")
        let unrelated = ArchiveTag(name: "GoodLinks/00daily")
        let file = ArchiveFile(
            originalFileName: "a.txt",
            tagIDs: [removed.id],
            detectedFormat: .plainText
        )
        let repository = InMemoryArchiveRepository(files: [file], tags: [removed, unrelated])
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await viewModel.load()

        await viewModel.setTag(removed.id, on: [file.id], isOn: false)

        let stored = await repository.fetchSnapshot()
        XCTAssertEqual(stored.tags.map(\.id), [unrelated.id])
    }

    func testRenamingATagOntoAnotherNameIsRefused() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        _ = await viewModel.createTag(named: "Recipes")
        let other = await viewModel.createTag(named: "Letters")!

        await viewModel.renameTag(id: other.id, to: "recipes")

        XCTAssertNotNil(viewModel.tagErrorMessage)
        XCTAssertEqual(viewModel.tag(id: other.id)?.name, "Letters")
    }

    func testRenamingASyntheticTagPathRenamesEveryStoredDescendant() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        let ios = await viewModel.createTag(named: "Dev/Xcode/iOS")!
        let mac = await viewModel.createTag(named: "Dev/Xcode/macOS")!

        await viewModel.renameTagPath(
            at: TagPathNode.foldedKey("Dev/Xcode"),
            to: "Dev/Platforms"
        )

        XCTAssertEqual(viewModel.tag(id: ios.id)?.name, "Dev/Platforms/iOS")
        XCTAssertEqual(viewModel.tag(id: mac.id)?.name, "Dev/Platforms/macOS")
        XCTAssertNil(viewModel.tagErrorMessage)
    }

    func testRenamingATagPathStopsBeforeAnySaveWhenADestinationConflicts() async {
        let (viewModel, repository) = makeViewModel()
        await viewModel.load()
        let ios = await viewModel.createTag(named: "Dev/Xcode/iOS")!
        let mac = await viewModel.createTag(named: "Dev/Xcode/macOS")!
        _ = await viewModel.createTag(named: "Dev/Platforms/iOS")

        await viewModel.renameTagPath(
            at: TagPathNode.foldedKey("Dev/Xcode"),
            to: "Dev/Platforms"
        )

        XCTAssertEqual(viewModel.tag(id: ios.id)?.name, "Dev/Xcode/iOS")
        XCTAssertEqual(viewModel.tag(id: mac.id)?.name, "Dev/Xcode/macOS")
        XCTAssertNotNil(viewModel.tagErrorMessage)
        let stored = await repository.fetchSnapshot()
        XCTAssertEqual(stored.tags.first(where: { $0.id == ios.id })?.name, "Dev/Xcode/iOS")
        XCTAssertEqual(stored.tags.first(where: { $0.id == mac.id })?.name, "Dev/Xcode/macOS")
    }

    /// The number beside a row is how many rows opening it shows: the folders in it and the files
    /// in it, and nothing from further down. Unsorted is not a folder and the folders at the top of
    /// the tree are not inside it, so it counts only its own files.
    func testAFolderCountsTheRowsItOpensOnto() async {
        let parent = ArchiveFolder(name: "Prompts")
        let child = ArchiveFolder(name: "Drafts", parentFolderID: parent.id)
        let inParent = ArchiveFile(
            originalFileName: "a.txt",
            parentFolderID: parent.id,
            detectedFormat: .plainText
        )
        let inChild = ArchiveFile(
            originalFileName: "b.txt",
            parentFolderID: child.id,
            detectedFormat: .plainText
        )
        let atRoot = ArchiveFile(originalFileName: "c.txt", detectedFormat: .plainText)
        // An empty folder counts as a row too, and is what tells this rule from counting the whole
        // subtree — that would say 2 here as well.
        let empty = ArchiveFolder(name: "Empty", parentFolderID: parent.id)
        let repository = InMemoryArchiveRepository(
            folders: [parent, child, empty],
            files: [inParent, inChild, atRoot]
        )
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.itemCount(inFolderWithID: parent.id), 3)
        XCTAssertEqual(viewModel.itemCount(inFolderWithID: child.id), 1)
        XCTAssertEqual(viewModel.itemCount(inFolderWithID: nil), 1)
    }

    /// A tag shows one level, as a folder does: the files given its own name, and the steps under
    /// it as rows. Gathering every descendant's files made a tag the one pane in the archive that
    /// showed what was not at the level it was showing.
    func testAParentTagListsItsOwnFilesAndLeavesTheRestToTheStepBelow() async {
        let onParent = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let onChild = ArchiveFile(originalFileName: "b.txt", detectedFormat: .plainText)
        let repository = InMemoryArchiveRepository(folders: [], files: [onParent, onChild])
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await viewModel.load()
        // Each tag is put on its file as soon as it is made: a tag nothing carries is swept away,
        // which is what an attribute rather than a container means.
        let parent = await viewModel.createTag(named: "Dev")!
        await viewModel.setTag(parent.id, on: [onParent.id], isOn: true)
        let child = await viewModel.createTag(named: "Dev/Xcode")!
        await viewModel.setTag(child.id, on: [onChild.id], isOn: true)

        XCTAssertEqual(viewModel.files(taggedWithPath: "dev").map(\.id), [onParent.id])
        XCTAssertEqual(viewModel.files(taggedWithPath: "dev/xcode").map(\.id), [onChild.id])
        // What the reader sees on the row: one file of its own, and one step further in.
        XCTAssertEqual(viewModel.tagNode(atPath: "dev")?.itemCount, 2)
        XCTAssertEqual(viewModel.tagNode(atPath: "dev/xcode")?.itemCount, 1)
        // The heading is the tree itself. It holds no files, and never did hold them at a level.
        XCTAssertTrue(viewModel.files(taggedWithPath: "").isEmpty)
    }

    /// Every archive exported before tags existed is still a backup of a whole archive.
    func testABackupWrittenBeforeTagsStillReads() throws {
        let json = """
        {
          "format": "io.github.inadaman.ArchiveLeaf.backup",
          "schemaVersion": 1,
          "createdAt": 744000000,
          "folders": [],
          "files": [
            {
              "assetRelativePath": "Assets/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.data",
              "file": {
                "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                "originalFileName": "note.txt",
                "isFavorite": false,
                "isTrashed": false,
                "detectedFormat": "plainText",
                "importedAt": 744000000,
                "fileSize": 12,
                "contentHash": "abc",
                "importState": "completed",
                "createdAt": 744000000,
                "updatedAt": 744000000
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(
            ArchiveBackupManifest.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(manifest.tags.isEmpty)
        XCTAssertEqual(manifest.files.first?.file.tagIDs, [])
        XCTAssertEqual(manifest.files.first?.file.originalFileName, "note.txt")
    }

    /// The same sorting the file list uses: choosing a tag changes which files are gathered, not
    /// how they are shown.
    func testATagsFilesFollowTheFileListsOrder() async {
        let b = ArchiveFile(originalFileName: "b.txt", detectedFormat: .plainText)
        let a = ArchiveFile(originalFileName: "a.txt", detectedFormat: .plainText)
        let (viewModel, _) = makeViewModel(files: [b, a])
        await viewModel.load()
        let tag = await viewModel.createTag(named: "Recipes")!
        await viewModel.setTag(tag.id, on: [a.id, b.id], isOn: true)

        viewModel.sortMode = .displayName
        viewModel.sortAscending = false

        XCTAssertEqual(viewModel.files(taggedWithPath: TagPathNode.foldedKey(tag.name)).map(\.id), [b.id, a.id])
    }
}
