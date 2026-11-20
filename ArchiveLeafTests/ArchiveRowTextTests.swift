import Foundation
import XCTest
@testable import ArchiveLeaf

@MainActor
final class ArchiveRowTextTests: XCTestCase {
    private func makeViewModel(
        folders: [ArchiveFolder] = [],
        files: [ArchiveFile] = [],
        tags: [ArchiveTag] = []
    ) async -> ArchiveViewModel {
        let repository = InMemoryArchiveRepository(folders: folders, files: files, tags: tags)
        let viewModel = ArchiveViewModel(
            repository: repository,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        await viewModel.load()
        return viewModel
    }

    func testMarksNameThePlaceThenTheFavouriteThenTheTags() async {
        let folder = ArchiveFolder(name: "Documents")
        let notes = ArchiveTag(name: "Notes")
        let file = ArchiveFile(
            originalFileName: "welcome.md",
            parentFolderID: folder.id,
            tagIDs: [notes.id],
            isFavorite: true,
            detectedFormat: .markdown
        )
        let viewModel = await makeViewModel(folders: [folder], files: [file], tags: [notes])

        let marks = ArchiveRowText.marks(on: file, viewModel: viewModel)

        XCTAssertEqual(marks.map(\.symbol), ["folder", "star.fill", "tag"])
        XCTAssertEqual(marks.map(\.text), ["Documents", "", "Notes"])
    }

    func testAFileOutsideEveryFolderIsMarkedWithTheTrayTheSidebarUses() async {
        let file = ArchiveFile(originalFileName: "loose.txt", detectedFormat: .plainText)
        let viewModel = await makeViewModel(files: [file])

        let marks = ArchiveRowText.marks(on: file, viewModel: viewModel)

        XCTAssertEqual(marks.map(\.symbol), ["tray"])
    }

    #if os(macOS)
    private static let font = NSFont.preferredFont(forTextStyle: .caption1)

    private static let marks = [
        ArchiveRowMark(symbol: "folder", text: "Screenshots and captures"),
        ArchiveRowMark(symbol: "tag", text: "Dev/Xcode/iOS")
    ]

    /// A line may end between two marks and nowhere else, so half a tag name never appears on a
    /// line of its own.
    func testALineMayOnlyBreakBetweenTwoMarks() {
        let line = ArchiveRowText.line(Self.marks, font: Self.font, colour: .labelColor).string

        let marks = line.components(separatedBy: "  ")
        XCTAssertEqual(marks.count, 2, "The separator between marks is the one break offered")
        for mark in marks {
            XCTAssertFalse(mark.contains(" "), "A mark must offer no break of its own")
        }
    }

    /// The joins are invisible: the reader sees the name that was stored.
    func testJoiningLeavesTheTextAsItReads() {
        let line = ArchiveRowText.line(Self.marks, font: Self.font, colour: .labelColor).string

        let plain = line
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertTrue(plain.contains("Screenshots and captures"))
        XCTAssertTrue(plain.contains("Dev/Xcode/iOS"))
    }

    /// A mark too long for a whole line is the one case joining cannot answer, so it is shortened
    /// until it fits — and only that mark.
    func testAMarkTooLongForOneLineIsShortenedToFitIt() {
        let long = ArchiveRowMark(
            symbol: "tag",
            text: "A very long tag name that cannot fit on a single line at all"
        )
        let width: CGFloat = 120

        let line = ArchiveRowText.line(
            [long],
            font: Self.font,
            colour: .labelColor,
            fittingWidth: width
        )

        XCTAssertLessThanOrEqual(line.size().width, width)
        XCTAssertTrue(line.string.contains("…"), "What was taken out has to show")
        let plain = line.string.replacingOccurrences(of: "\u{2060}", with: "")
        XCTAssertTrue(plain.hasSuffix("all"), "A tag keeps its end, which says most")
    }

    func testAMarkThatFitsIsLeftAlone() {
        let width: CGFloat = 400

        let line = ArchiveRowText.line(
            Self.marks,
            font: Self.font,
            colour: .labelColor,
            fittingWidth: width
        )

        XCTAssertFalse(line.string.contains("…"))
    }
    #endif
}
