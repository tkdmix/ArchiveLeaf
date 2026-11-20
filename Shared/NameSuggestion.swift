import Foundation

/// Turns shared text into a starting point for a file name.
///
/// A suggestion, never a decision: the field it fills stays editable, so nothing is named by
/// guesswork alone. Without this the user would face an empty box for every scrap of text.
enum NameSuggestion {
    static let maximumLength = 60

    static func fileName(forSharedText text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // "/" and ":" are not usable in a file name on this platform.
        let cleaned = firstLine
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty else { return String(localized: "Shared Text") }
        return cleaned.count <= maximumLength
            ? cleaned
            : String(cleaned.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
    }
}
