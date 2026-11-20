import Foundation

/// Interprets the conservative text representations used by share providers for web pages.
///
/// Some browsers publish a page as `public.url`; others publish the address as plain text, often
/// alongside a title. ArchiveLeaf only needs the address. Requiring the address to occupy a whole
/// line avoids turning an arbitrary sentence containing a link into a bookmark.
enum SharedURLInterpretation {
    static func webURL(from text: String) -> URL? {
        let lines = text.components(separatedBy: .newlines)
        // Evaluate individual lines first. URLComponents can percent-encode an embedded newline
        // and accidentally absorb a following page title into the URL path.
        let candidates = lines.count > 1 ? lines : [text]
        for candidate in candidates {
            if let url = try? BookmarkDocument.webURL(from: candidate) {
                return url
            }
        }
        return nil
    }
}
