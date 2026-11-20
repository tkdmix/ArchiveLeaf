import Foundation

/// Reads a GoodLinks JSON export.
///
/// GoodLinks has no folders, so nothing here produces a folder path: everything lands in the one
/// folder named after the app. Its tags already carry their own outline — `00daily/0-srch` — and
/// that is the same slash the shelf reads, so they arrive intact under the source's branch.
///
/// The summary, the reading state, and the address a redirect started from are dropped. `url` is
/// where the bookmark goes; `originalURL` is where the user came from, which the shelf has nowhere
/// to say.
struct GoodLinksJSONParser {
    private struct Item: Decodable {
        let url: String
        let title: String?
        let tags: [String]?
        let starred: Bool?
        let addedAt: Double?
    }

    func bookmarks(from data: Data) throws -> ParsedBookmarkFile {
        let items: [Item]
        do {
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            throw BookmarkImportError.unrecognizedFormat
        }
        guard !items.isEmpty else { throw BookmarkImportError.emptyFile }

        var unreadableCount = 0
        let bookmarks: [ImportedBookmark] = items.compactMap { item in
            guard let url = try? BookmarkDocument.webURL(from: item.url) else {
                unreadableCount += 1
                return nil
            }
            return ImportedBookmark(
                title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                url: url,
                tagNames: (item.tags ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                isFavorite: item.starred ?? false,
                addedAt: item.addedAt.map { Date(timeIntervalSince1970: $0) }
            )
        }
        return ParsedBookmarkFile(bookmarks: bookmarks, unreadableCount: unreadableCount)
    }
}
