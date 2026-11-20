import Foundation

/// Brings bookmarks in from another app's export file.
protocol BookmarkImporting: Sendable {
    func importBookmarks(
        from fileURL: URL,
        source: BookmarkImportSource
    ) async throws -> BookmarkImportSummary
}

struct ParsedBookmarkFile: Sendable {
    let bookmarks: [ImportedBookmark]
    /// Rows the export held that carry no usable web address.
    let unreadableCount: Int
}

/// What the import did, said in whole numbers.
///
/// Four outcomes rather than one, because "57 bookmarks, 12 imported" is only an alarming number
/// until it says the other 45 were already on the shelf. The archive as it now stands travels with
/// them, so the shelf can show the result without reading CloudKit again — its index trails its own
/// writes, and a read here would show an archive missing what was just written.
struct BookmarkImportSummary: Sendable {
    let source: BookmarkImportSource
    let importedCount: Int
    let duplicateCount: Int
    let unreadableCount: Int
    let failures: [String]
    let snapshot: ArchiveSnapshot

    var totalCount: Int { importedCount + duplicateCount + unreadableCount + failures.count }
}

enum BookmarkImportError: LocalizedError {
    case unreadableFile
    case emptyFile
    case unrecognizedFormat
    case fileSizeExceeded(Int64)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            String(localized: "The export could not be read as text.")
        case .emptyFile:
            String(localized: "The export contains no bookmarks.")
        case .unrecognizedFormat:
            String(localized: "This file is not an export from that app.")
        case .fileSizeExceeded(let limit):
            String(localized: "The export exceeds the \(limit.formatted(.byteCount(style: .file))) limit.")
        }
    }
}
