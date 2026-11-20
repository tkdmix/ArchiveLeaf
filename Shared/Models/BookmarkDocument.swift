import Foundation

/// The one value ArchiveLeaf needs from a standard `.webloc` property list.
///
/// The page itself is never fetched. Keeping the standard file as the immutable asset means a
/// bookmark can be exported, shared, backed up and opened outside ArchiveLeaf without conversion.
enum BookmarkDocument {
    static func url(from data: Data) throws -> URL {
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = propertyList as? [String: Any],
              let value = dictionary["URL"] as? String else {
            throw BookmarkDocumentError.missingURL
        }
        return try webURL(from: value)
    }

    static func data(for url: URL) throws -> Data {
        let validated = try webURL(from: url.absoluteString)
        return try PropertyListSerialization.data(
            fromPropertyList: ["URL": validated.absoluteString],
            format: .xml,
            options: 0
        )
    }

    static func webURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              let url = components.url else {
            throw BookmarkDocumentError.invalidWebURL
        }
        return url
    }

    /// Produces the familiar Finder-style suffix only when the useful, short host name is already
    /// present. URL identity remains the bookmark data's job; this only keeps sibling names valid.
    static func uniqueTitle(for url: URL, among existingNames: Set<String>) -> String {
        let base = url.host ?? String(localized: "Bookmark")
        let normalizedNames = Set(existingNames.map(ArchiveRules.normalizedName))
        guard normalizedNames.contains(ArchiveRules.normalizedName(base)) else { return base }

        var suffix = 2
        while normalizedNames.contains(ArchiveRules.normalizedName("\(base) \(suffix)")) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    /// Writes one standard bookmark asset. Callers stage separate incoming items in separate
    /// directories, so the visible title remains clean instead of acquiring a storage suffix.
    static func write(
        url: URL,
        title: String? = nil,
        into directory: URL
    ) throws -> URL {
        let validated = try webURL(from: url.absoluteString)
        let enteredTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = enteredTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? validated.host
            ?? String(localized: "Bookmark")
        let baseName = safeFileName(for: resolvedTitle)
        let destination = directory.appendingPathComponent("\(baseName).webloc", isDirectory: false)
        try data(for: validated).write(to: destination, options: .atomic)
        return destination
    }

    static func safeFileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\n\r")
        let safe = title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((safe.isEmpty ? String(localized: "Bookmark") : safe).prefix(180))
    }
}

enum BookmarkDocumentError: LocalizedError {
    case missingURL
    case invalidWebURL

    var errorDescription: String? {
        switch self {
        case .missingURL:
            String(localized: "The bookmark does not contain a URL.")
        case .invalidWebURL:
            String(localized: "Enter a complete HTTP or HTTPS URL.")
        }
    }
}
