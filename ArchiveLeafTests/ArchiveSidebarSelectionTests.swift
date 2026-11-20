#if os(macOS)
// The Mac's sidebar, and the functions that map its presentation values onto the canonical
// browsing location. The whole file is macOS-only because those functions are: iOS and iPadOS
// reach the same state through a tab bar and a navigation stack instead.
import Foundation
import XCTest
@testable import ArchiveLeaf

final class ArchiveSidebarSelectionTests: XCTestCase {
    func testSidebarSourceAndLocationMappingRoundTrip() {
        let folderID = UUID()
        let locations: [ArchiveBrowsingLocation] = [
            .folders,
            .unsorted,
            .folder(folderID),
            .favorites,
            .tag(path: ""),
            .tag(path: "Work/ArchiveLeaf"),
            .trash,
        ]

        for location in locations {
            XCTAssertEqual(archiveBrowsingLocation(for: archiveSource(for: location)), location)
        }
        XCTAssertNil(archiveBrowsingLocation(for: nil))
    }

    func testColumnRootSourceIsDerivedFromLocation() {
        XCTAssertEqual(archiveRootSource(for: .folders), .folders)
        XCTAssertEqual(archiveRootSource(for: .unsorted), .folders)
        XCTAssertEqual(archiveRootSource(for: .folder(UUID())), .folders)
        XCTAssertEqual(archiveRootSource(for: .favorites), .favorites)
        XCTAssertEqual(archiveRootSource(for: .tag(path: "Work")), .tag(path: ""))
        XCTAssertEqual(archiveRootSource(for: .trash), .trash)
    }

    func testRoutePathIsDerivedFromLocation() {
        let rootFolderID = UUID()
        let childFolderID = UUID()

        XCTAssertEqual(
            archiveRoutePath(
                for: .folder(childFolderID),
                folderIDs: [rootFolderID, childFolderID],
                tagPaths: []
            ),
            [.folder(rootFolderID), .folder(childFolderID)]
        )
        XCTAssertEqual(
            archiveRoutePath(for: .unsorted, folderIDs: [], tagPaths: []),
            [.unsorted]
        )
        XCTAssertEqual(
            archiveRoutePath(
                for: .tag(path: "Work/ArchiveLeaf"),
                folderIDs: [],
                tagPaths: ["Work", "Work/ArchiveLeaf"]
            ),
            [.tag(path: "Work"), .tag(path: "Work/ArchiveLeaf")]
        )
        XCTAssertEqual(archiveRoutePath(for: .favorites, folderIDs: [], tagPaths: []), [])
    }

    func testColumnPathWritesLocationAndPopsToItsCorrectRoot() {
        let folderID = UUID()

        XCTAssertEqual(
            archiveBrowsingLocation(forColumnPath: [.folder(folderID)], from: .folders),
            .folder(folderID)
        )
        XCTAssertEqual(
            archiveBrowsingLocation(forColumnPath: [.unsorted], from: .folders),
            .unsorted
        )
        XCTAssertEqual(
            archiveBrowsingLocation(
                forColumnPath: [.tag(path: "Work/ArchiveLeaf")],
                from: .tag(path: "")
            ),
            .tag(path: "Work/ArchiveLeaf")
        )
        XCTAssertEqual(archiveBrowsingLocation(forColumnPath: [], from: .folder(folderID)), .folders)
        XCTAssertEqual(
            archiveBrowsingLocation(forColumnPath: [], from: .tag(path: "Work/ArchiveLeaf")),
            .tag(path: "")
        )
        XCTAssertEqual(archiveBrowsingLocation(forColumnPath: [], from: .favorites), .favorites)
        XCTAssertEqual(archiveBrowsingLocation(forColumnPath: [], from: .trash), .trash)
    }

    func testFileRouteDoesNotChangeTheListLocation() {
        XCTAssertNil(
            archiveBrowsingLocation(
                forColumnPath: [.file(UUID())],
                from: .folder(UUID())
            )
        )
    }
}
#endif
