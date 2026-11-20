import Foundation

enum ArchiveRules {
    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .localizedLowercase
    }
}
