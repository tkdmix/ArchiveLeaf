import Foundation

struct DocumentSearch: Sendable {
    func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        var results: [NSRange] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            results.append(NSRange(range, in: text))
            searchRange = range.upperBound..<text.endIndex
        }
        return results
    }
}
