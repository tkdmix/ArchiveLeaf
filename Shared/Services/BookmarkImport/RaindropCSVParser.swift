import Foundation

/// Reads a Raindrop.io CSV export.
///
/// Columns are found by their heading rather than by position, so a column added or moved by a
/// later Raindrop release does not silently shift every value one place. Only the address is
/// required; a row without a usable one is reported as unreadable rather than stored as a bookmark
/// pointing nowhere.
///
/// What Raindrop keeps and the shelf does not — the note, the excerpt, the cover image, the
/// highlights, its own identifier — is dropped here, deliberately and in one place. The shelf does
/// not fetch pages, so a cover would have to be downloaded to mean anything.
struct RaindropCSVParser {
    func bookmarks(from data: Data) throws -> ParsedBookmarkFile {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BookmarkImportError.unreadableFile
        }
        let rows = SeparatedValues.rows(from: text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let heading = rows.first else { throw BookmarkImportError.emptyFile }

        let columns = Dictionary(
            heading.enumerated().map { ($0.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let urlColumn = columns["url"] else { throw BookmarkImportError.unrecognizedFormat }

        var unreadableCount = 0
        let bookmarks: [ImportedBookmark] = rows.dropFirst().compactMap { row in
            func value(_ column: String) -> String {
                guard let index = columns[column], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard urlColumn < row.count,
                  let url = try? BookmarkDocument.webURL(from: row[urlColumn]) else {
                unreadableCount += 1
                return nil
            }

            return ImportedBookmark(
                title: value("title"),
                url: url,
                folderPathComponents: BookmarkImportNames.pathComponents(value("folder")),
                tagNames: value("tags")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                isFavorite: value("favorite").lowercased() == "true",
                addedAt: Self.date(from: value("created"))
            )
        }
        return ParsedBookmarkFile(bookmarks: bookmarks, unreadableCount: unreadableCount)
    }

    /// Raindrop writes `2026-04-11T02:14:34.000Z`. Older exports leave the fraction off, so both
    /// are read rather than the date being lost to a format difference.
    static func date(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
