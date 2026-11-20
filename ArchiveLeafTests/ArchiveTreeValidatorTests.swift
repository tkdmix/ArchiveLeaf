import XCTest
@testable import ArchiveLeaf

final class ArchiveTreeValidatorTests: XCTestCase {
    func testRejectsFileNameMatchingSiblingFolder() {
        let folder = ArchiveFolder(name: "Notes")
        let file = ArchiveFile(originalFileName: "notes.txt", detectedFormat: .plainText)
        let snapshot = ArchiveSnapshot(folders: [folder], files: [])

        XCTAssertThrowsError(try ArchiveTreeValidator.validate(file: file, in: snapshot)) { error in
            XCTAssertEqual(error as? ArchiveValidationError, .duplicateName)
        }
    }

    func testAllowsFolderBelowTheFormerFifthLevelLimit() {
        let first = ArchiveFolder(name: "1")
        let second = ArchiveFolder(name: "2", parentFolderID: first.id)
        let third = ArchiveFolder(name: "3", parentFolderID: second.id)
        let fourth = ArchiveFolder(name: "4", parentFolderID: third.id)
        let fifth = ArchiveFolder(name: "5", parentFolderID: fourth.id)
        let sixth = ArchiveFolder(name: "6", parentFolderID: fifth.id)
        let snapshot = ArchiveSnapshot(
            folders: [first, second, third, fourth, fifth],
            files: []
        )

        XCTAssertNoThrow(try ArchiveTreeValidator.validate(folder: sixth, in: snapshot))
    }

    func testRejectsMovingFolderIntoDescendant() {
        var parent = ArchiveFolder(name: "Parent")
        let child = ArchiveFolder(name: "Child", parentFolderID: parent.id)
        let snapshot = ArchiveSnapshot(folders: [parent, child], files: [])
        parent.parentFolderID = child.id

        XCTAssertThrowsError(try ArchiveTreeValidator.validate(folder: parent, in: snapshot)) { error in
            XCTAssertEqual(error as? ArchiveValidationError, .cyclicFolderReference)
        }
    }
}
