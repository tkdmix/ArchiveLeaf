import Foundation

/// One bookmark read out of another app's export, before anything is put in the shelf.
///
/// The exporting app's own words, kept apart from the archive's: the folder path and tag names
/// here are what the file said, without the source's name in front of them. Where that name is
/// added is the importer's decision, and it is made once.
struct ImportedBookmark: Hashable, Sendable {
    let title: String
    let url: URL
    /// Below the source's own folder. Empty where the exporting app has no folders.
    let folderPathComponents: [String]
    /// As the source wrote them, slashes and all. The source's name is not among them.
    let tagNames: [String]
    let isFavorite: Bool
    /// When the source says it was saved. Kept as the file's source date; the import date remains
    /// the moment it arrived here.
    let addedAt: Date?

    init(
        title: String,
        url: URL,
        folderPathComponents: [String] = [],
        tagNames: [String] = [],
        isFavorite: Bool = false,
        addedAt: Date? = nil
    ) {
        self.title = title
        self.url = url
        self.folderPathComponents = folderPathComponents
        self.tagNames = tagNames
        self.isFavorite = isFavorite
        self.addedAt = addedAt
    }
}
