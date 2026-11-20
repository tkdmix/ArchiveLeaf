import CryptoKit
import Foundation
#if os(iOS)
import UIKit
#endif

struct AppEnvironment: Sendable {
    let archiveRepository: any ArchiveRepository
    let importPreflight: any ImportPreflightChecking
    let archiveImporter: any ArchiveImporting
    let bookmarkImporter: any BookmarkImporting
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: any ArchiveCaching
    let snapshotCache: any ArchiveSnapshotCaching
    let connectivity: any ConnectivityChecking

    @MainActor
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppEnvironment {
        if environment["ARCHIVELEAF_DATA_SOURCE"]?.lowercased() == "memory" {
            return makePreview(
                firstFileStartsInTrash: environment["ARCHIVELEAF_UI_TEST_TRASH"] == "1",
                includesBrowserFailureLink: environment["ARCHIVELEAF_UI_TEST_BROWSER_FAILURE"] == "1"
            )
        }

        let repository = CloudKitArchiveRepository()
        let cache = makeCache()
        let snapshotCache = makeSnapshotCache()
        return AppEnvironment(
            archiveRepository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            ),
            archiveImporter: ArchiveImportService(repository: repository),
            bookmarkImporter: BookmarkImportService(repository: repository),
            archiveResetter: repository,
            incompleteImportPurger: repository,
            archiveBackupService: ArchiveBackupPackageService(repository: repository),
            archiveCache: cache,
            snapshotCache: snapshotCache,
            connectivity: NetworkConnectivityMonitor()
        )
    }

    @MainActor static let preview = makePreview(
        firstFileStartsInTrash: false,
        includesBrowserFailureLink: false
    )

    @MainActor
    private static func makePreview(
        firstFileStartsInTrash: Bool,
        includesBrowserFailureLink: Bool
    ) -> AppEnvironment {
        let documents = ArchiveFolder(name: "Documents", folderSortIndex: 0)
        let images = ArchiveFolder(name: "Images", folderSortIndex: 1)
        // Nested, so that anything to do with depth — going in, going up, a folder listed among
        // files — can be tried without first building a tree by hand.
        let drafts = ArchiveFolder(name: "Drafts", parentFolderID: documents.id, folderSortIndex: 0)
        let welcomeContent = if includesBrowserFailureLink {
            "# Welcome to ArchiveLeaf\n\n[Open unavailable test page](https://127.0.0.1:1/)\n"
        } else {
            "# Welcome to ArchiveLeaf\n\nSelect an imported file to view its immutable content.\n"
        }
        // Sizes and hashes are derived from the bytes below rather than invented, so that paths
        // which verify an asset against its recorded metadata — backup export — also work here.
        // One tag, on the file that is also the sample favorite: the same file reached three ways —
        // through its folder, through Favorites, through a tag — is what the lists are meant to
        // agree about, and without a tag here the tag pane could not be driven at all.
        let notes = ArchiveTag(name: "Notes")
        // A tag one step below another, so the pseudo-hierarchy can be driven here too: a tag pane
        // shows the steps under it and the files given its own name, and neither half of that
        // sentence could be seen on a shelf whose tags were all flat.
        let ideas = ArchiveTag(name: "Notes/Ideas")
        let welcomeData = Data(welcomeContent.utf8)
        let sampleData = Data("{\"name\":\"ArchiveLeaf\",\"platforms\":[\"macOS\",\"iOS\",\"iPadOS\"]}".utf8)
        // Two bookmarks among the samples. One, because it is the item whose behaviour differs on
        // every platform — a browser pane on the Mac, a full-screen Safari view on iOS and iPadOS —
        // and none of that could be tried without one already on the shelf. Two, because going from
        // one bookmark straight to another is its own case: the pane is not rebuilt between them,
        // and it once answered the second with the first one's page.
        let bookmarkData = (try? BookmarkDocument.data(for: URL(string: "https://example.com")!)) ?? Data()
        let otherBookmarkData = (try? BookmarkDocument.data(for: URL(string: "https://example.net")!)) ?? Data()
        // Four pages that do not agree about their shape, so that fitting a page and fitting the
        // width are visibly different acts, and so that each is measured against the page the
        // reader is on rather than the first one.
        let mixedPagesData = SamplePDFDocument.data()
        let landscapeData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()

        let files = [
            ArchiveFile(
                originalFileName: "welcome.md",
                userDefinedName: "Welcome",
                parentFolderID: documents.id,
                originalParentFolderID: firstFileStartsInTrash ? documents.id : nil,
                tagIDs: [notes.id],
                isFavorite: true,
                isTrashed: firstFileStartsInTrash,
                trashedAt: firstFileStartsInTrash ? .now : nil,
                detectedFormat: .markdown,
                fileSize: Int64(welcomeData.count),
                contentHash: sha256Hex(welcomeData)
            ),
            ArchiveFile(
                originalFileName: "sample.json",
                userDefinedName: "Sample Data",
                parentFolderID: documents.id,
                tagIDs: [ideas.id],
                detectedFormat: .json,
                fileSize: Int64(sampleData.count),
                contentHash: sha256Hex(sampleData)
            ),
            ArchiveFile(
                originalFileName: "example.com.webloc",
                userDefinedName: "example.com",
                parentFolderID: documents.id,
                detectedFormat: .bookmark,
                fileSize: Int64(bookmarkData.count),
                contentHash: sha256Hex(bookmarkData)
            ),
            ArchiveFile(
                originalFileName: "example.net.webloc",
                userDefinedName: "example.net",
                parentFolderID: documents.id,
                detectedFormat: .bookmark,
                fileSize: Int64(otherBookmarkData.count),
                contentHash: sha256Hex(otherBookmarkData)
            ),
            ArchiveFile(
                originalFileName: "mixed-pages.pdf",
                userDefinedName: "Mixed Pages",
                parentFolderID: documents.id,
                detectedFormat: .pdf,
                fileSize: Int64(mixedPagesData.count),
                contentHash: sha256Hex(mixedPagesData)
            ),
            ArchiveFile(
                originalFileName: "landscape.png",
                userDefinedName: "Landscape",
                parentFolderID: images.id,
                detectedFormat: .png,
                fileSize: Int64(landscapeData.count),
                contentHash: sha256Hex(landscapeData)
            )
        ]
        let previewAssets: [UUID: Data] = [
            files[0].id: welcomeData,
            files[1].id: sampleData,
            files[2].id: bookmarkData,
            files[3].id: otherBookmarkData,
            files[4].id: mixedPagesData,
            files[5].id: landscapeData
        ]
        let repository = InMemoryArchiveRepository(
            folders: [documents, images, drafts],
            files: files,
            tags: [notes, ideas],
            assetDataByFileID: previewAssets
        )
        return AppEnvironment(
            archiveRepository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            ),
            archiveImporter: ArchiveImportService(repository: repository),
            bookmarkImporter: BookmarkImportService(repository: repository),
            archiveResetter: nil,
            incompleteImportPurger: nil,
            archiveBackupService: ArchiveBackupPackageService(repository: repository),
            archiveCache: makeCache(),
            snapshotCache: makeSnapshotCache(),
            connectivity: AlwaysOnlineConnectivity()
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func makeCache() -> any ArchiveCaching {
        #if os(macOS)
        let platform: CachePolicy.Platform = .macOS
        #else
        let platform: CachePolicy.Platform = UIDevice.current.userInterfaceIdiom == .pad ? .iPadOS : .iOS
        #endif
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cache = DiskArchiveCache(
            directoryURL: baseURL
                .appendingPathComponent("ArchiveLeaf", isDirectory: true)
                .appendingPathComponent("FileContent", isDirectory: true),
            policy: .standard(for: platform)
        )
        return ArchiveCacheWithLegacyTemporaryCleanup(cache: cache)
    }

    private static func makeSnapshotCache() -> DiskArchiveSnapshotCache {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return DiskArchiveSnapshotCache(
            fileURL: baseURL
                .appendingPathComponent("ArchiveLeaf", isDirectory: true)
                .appendingPathComponent("Metadata", isDirectory: true)
                .appendingPathComponent("snapshot.json", isDirectory: false)
        )
    }
}
