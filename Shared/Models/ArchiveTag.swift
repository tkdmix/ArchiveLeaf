import Foundation

/// A label put on files, across whatever folders they sit in.
///
/// A tag does not replace a folder. A file lives in one folder and carries any number of tags, so
/// the folder answers "where is it" and the tag answers "what is it about". Both resolve to the
/// same thing on screen: a list of files in the middle pane.
struct ArchiveTag: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
