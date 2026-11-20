import Foundation
import UniformTypeIdentifiers

/// A bookmarking app ArchiveLeaf can read an export from.
///
/// Each source keeps its own folder and its own branch of the tag tree, named after the app. What
/// was imported stays separate from what the shelf already had: a `macOS` tag put on here and a
/// `macOS` tag that arrived from Raindrop are two rows, and neither quietly absorbs the other.
enum BookmarkImportSource: String, CaseIterable, Identifiable, Sendable {
    case raindrop
    case goodLinks

    var id: String { rawValue }

    /// The folder every imported bookmark lands under, and the first step of every imported tag.
    var name: String {
        switch self {
        case .raindrop: "Raindrop"
        case .goodLinks: "GoodLinks"
        }
    }

    /// What the file chooser accepts. Both exports are plain text, so the type is what tells them
    /// apart — the reader has already said which app the file came from.
    var contentType: UTType {
        switch self {
        case .raindrop: .commaSeparatedText
        case .goodLinks: .json
        }
    }

    func parseBookmarks(from data: Data) throws -> ParsedBookmarkFile {
        switch self {
        case .raindrop: try RaindropCSVParser().bookmarks(from: data)
        case .goodLinks: try GoodLinksJSONParser().bookmarks(from: data)
        }
    }

    /// The stored tag name for one of the source's tags: its own branch, then what the source said.
    ///
    /// One name with slashes in it, which is all the archive stores. The outline the reader sees is
    /// derived from that name, so putting the source at the front needs no new field anywhere.
    func tagName(for sourceTagName: String) -> String? {
        let components = BookmarkImportNames.pathComponents(sourceTagName)
        guard !components.isEmpty else { return nil }
        return ([name] + components).joined(separator: "/")
    }
}

enum BookmarkImportNames {
    /// Splits a source's folder or tag value into shelf-safe steps.
    ///
    /// A slash means one level down in both apps' tags and in ArchiveLeaf's, so it is kept as the
    /// separator rather than escaped. Empty steps are dropped instead of refused: `a//b` is the
    /// exporting app's typo, not a reason to lose the bookmark.
    static func pathComponents(_ value: String) -> [String] {
        value
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
