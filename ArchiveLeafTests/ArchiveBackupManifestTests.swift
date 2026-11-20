import XCTest
@testable import ArchiveLeaf

final class ArchiveBackupManifestTests: XCTestCase {
    func testManifestRoundTripPreservesMetadata() throws {
        let folder = ArchiveFolder(name: "Prompts")
        let file = ArchiveFile(
            originalFileName: "review.md",
            parentFolderID: folder.id,
            isFavorite: true,
            detectedFormat: .markdown,
            sourceEncoding: "utf-8",
            fileSize: 42,
            contentHash: "sha256"
        )
        let manifest = ArchiveBackupManifest(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            folders: [folder],
            files: [ArchiveBackupFileEntry(file: file)]
        )

        let coder = JSONArchiveBackupManifestCoder()
        let decoded = try coder.decode(coder.encode(manifest))

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(
            decoded.files[0].assetRelativePath,
            "Assets/\(file.id.uuidString.lowercased()).data"
        )
    }

    func testManifestRoundTripPreservesBookmarkFormat() throws {
        let file = ArchiveFile(
            originalFileName: "Reference.webloc",
            detectedFormat: .bookmark,
            fileSize: 128,
            contentHash: "bookmark-hash"
        )
        let manifest = ArchiveBackupManifest(
            folders: [],
            files: [ArchiveBackupFileEntry(file: file)]
        )
        let coder = JSONArchiveBackupManifestCoder()

        let decoded = try coder.decode(coder.encode(manifest))

        XCTAssertEqual(decoded.files.first?.file.detectedFormat, .bookmark)
    }

    func testBackupFromAPIPrototypeIgnoresOptionalURLHint() throws {
        let file = ArchiveFile(originalFileName: "Saved.webloc", detectedFormat: .bookmark,
                               fileSize: 128, contentHash: "fixture-hash")
        let manifest = ArchiveBackupManifest(folders: [], files: [ArchiveBackupFileEntry(file: file)])
        let coder = JSONArchiveBackupManifestCoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: coder.encode(manifest)) as? [String: Any])
        var entries = try XCTUnwrap(object["files"] as? [[String: Any]])
        var metadata = try XCTUnwrap(entries[0]["file"] as? [String: Any])
        metadata["bookmarkURL"] = "https://example.test/preserved"
        entries[0]["file"] = metadata; object["files"] = entries
        let decoded = try coder.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, manifest)
    }

    func testRejectsUnsupportedSchemaBeforeRestore() throws {
        let manifest = ArchiveBackupManifest(
            schemaVersion: 999,
            folders: [],
            files: []
        )

        XCTAssertThrowsError(try ArchiveBackupManifestValidator().validate(manifest)) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .unsupportedSchemaVersion(999))
        }
    }

    func testRejectsIdentifierSharedByFolderAndFile() throws {
        let id = UUID()
        let folder = ArchiveFolder(id: id, name: "Folder")
        let file = ArchiveFile(id: id, originalFileName: "file.txt", detectedFormat: .plainText)

        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(
                    folders: [folder],
                    files: [ArchiveBackupFileEntry(file: file)]
                )
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .duplicateIdentifier)
        }
    }

    func testRejectsMissingParentAndCircularFolders() throws {
        let orphan = ArchiveFolder(name: "Orphan", parentFolderID: UUID())
        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(folders: [orphan], files: [])
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .missingParent(orphan.id))
        }

        let firstID = UUID()
        let secondID = UUID()
        let first = ArchiveFolder(id: firstID, name: "First", parentFolderID: secondID)
        let second = ArchiveFolder(id: secondID, name: "Second", parentFolderID: firstID)
        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(folders: [first, second], files: [])
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .folderCycle(first.id))
        }
    }

    func testRejectsIncompleteFileAndUnexpectedAssetPath() throws {
        let incomplete = ArchiveFile(
            originalFileName: "pending.txt",
            detectedFormat: .plainText,
            importState: .uploading
        )
        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(
                    folders: [],
                    files: [ArchiveBackupFileEntry(file: incomplete)]
                )
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .incompleteFile(incomplete.id))
        }

        let file = ArchiveFile(originalFileName: "safe.txt", detectedFormat: .plainText)
        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(
                    folders: [],
                    files: [ArchiveBackupFileEntry(file: file, assetRelativePath: "../safe.txt")]
                )
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .invalidAssetPath(file.id))
        }
    }

    func testRejectsTrashFromPortableBackup() throws {
        let folder = ArchiveFolder(name: "Deleted", isTrashed: true, trashedAt: .now)

        XCTAssertThrowsError(
            try ArchiveBackupManifestValidator().validate(
                ArchiveBackupManifest(folders: [folder], files: [])
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveBackupValidationError, .trashedItem(folder.id))
        }
    }

    func testDefaultFileNameUsesTheLocalClockNotUTC() throws {
        // 2026-08-06 07:14 in Tokyo is still 2026-08-05 22:14 in GMT — a different day and a
        // different hour, so one instant pins both fields at once.
        let instant = try XCTUnwrap(
            DateComponents(
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "Asia/Tokyo"),
                year: 2026, month: 8, day: 6, hour: 7, minute: 14
            ).date
        )

        XCTAssertEqual(
            ArchiveBackupPackage.defaultFileName(
                on: instant,
                in: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
            ),
            "ArchiveLeaf-Backup-2026-08-06-07-14"
        )
        XCTAssertEqual(
            ArchiveBackupPackage.defaultFileName(
                on: instant,
                in: try XCTUnwrap(TimeZone(identifier: "GMT"))
            ),
            "ArchiveLeaf-Backup-2026-08-05-22-14"
        )
    }
}
