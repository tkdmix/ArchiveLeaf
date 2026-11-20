import CloudKit
import XCTest
@testable import ArchiveLeaf

final class CloudKitRecordMapperTests: XCTestCase {
    func testExistingAPIPrototypeURLFieldIsIgnoredButNotErasedByMetadataSave() throws {
        let file = ArchiveFile(originalFileName: "Saved.webloc", detectedFormat: .bookmark,
                               fileSize: 128, contentHash: "fixture-hash")
        let record = CloudKitRecordMapper.record(from: file)
        record["bookmarkURL"] = "https://example.test/preserved" as CKRecordValue
        var decoded = try CloudKitRecordMapper.file(from: record)
        XCTAssertEqual(decoded, file)
        decoded.isFavorite = true
        CloudKitRecordMapper.update(record, from: decoded)
        XCTAssertEqual(record["bookmarkURL"] as? String, "https://example.test/preserved")
        XCTAssertFalse(CloudKitSchema.fileMetadataFields.contains("bookmarkURL"))
    }

    func testFolderRoundTripPreservesHierarchyMetadata() throws {
        let parentID = UUID()
        let folder = ArchiveFolder(
            name: "資料",
            parentFolderID: parentID,
            folderSortIndex: 3
        )

        let decoded = try CloudKitRecordMapper.folder(
            from: CloudKitRecordMapper.record(from: folder)
        )

        XCTAssertEqual(decoded.id, folder.id)
        XCTAssertEqual(decoded.name, folder.name)
        XCTAssertEqual(decoded.parentFolderID, parentID)
        XCTAssertEqual(decoded.folderSortIndex, 3)
    }

    func testFileRoundTripPreservesUserAndSystemMetadata() throws {
        let parentID = UUID()
        let file = ArchiveFile(
            originalFileName: "source.txt",
            userDefinedName: "Read Me",
            parentFolderID: parentID,
            isFavorite: true,
            detectedFormat: .plainText,
            displayFormatOverride: .markdown,
            sourceEncoding: "utf-8",
            sourceEncodingOverride: .windows31J,
            fileSize: 42,
            contentHash: "abc123"
        )

        let decoded = try CloudKitRecordMapper.file(
            from: CloudKitRecordMapper.record(from: file)
        )

        XCTAssertEqual(decoded.id, file.id)
        XCTAssertEqual(decoded.displayName, "Read Me")
        XCTAssertEqual(decoded.parentFolderID, parentID)
        XCTAssertTrue(decoded.isFavorite)
        XCTAssertEqual(decoded.detectedFormat, .plainText)
        XCTAssertEqual(decoded.displayFormatOverride, .markdown)
        XCTAssertEqual(decoded.sourceEncoding, "utf-8")
        XCTAssertEqual(decoded.sourceEncodingOverride, .windows31J)
        XCTAssertEqual(decoded.effectiveTextEncoding, .windows31J)
        XCTAssertEqual(decoded.fileSize, 42)
        XCTAssertEqual(decoded.contentHash, "abc123")
        XCTAssertEqual(decoded.importState, .completed)
    }

    func testFileRoundTripPreservesIncompleteImportState() throws {
        let file = ArchiveFile(
            originalFileName: "pending.txt",
            detectedFormat: .plainText,
            contentHash: "hash",
            importState: .uploading
        )

        let decoded = try CloudKitRecordMapper.file(from: CloudKitRecordMapper.record(from: file))

        XCTAssertEqual(decoded.importState, .uploading)
    }

    func testFileRoundTripPreservesBookmarkFormat() throws {
        let file = ArchiveFile(
            originalFileName: "Reference.webloc",
            detectedFormat: .bookmark,
            fileSize: 128,
            contentHash: "bookmark-hash"
        )

        let decoded = try CloudKitRecordMapper.file(from: CloudKitRecordMapper.record(from: file))

        XCTAssertEqual(decoded.detectedFormat, .bookmark)
    }
}
