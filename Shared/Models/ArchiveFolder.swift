import Foundation

struct ArchiveFolder: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var parentFolderID: UUID?
    var originalParentFolderID: UUID?
    var folderSortIndex: Int
    var isTrashed: Bool
    var trashedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        parentFolderID: UUID? = nil,
        originalParentFolderID: UUID? = nil,
        folderSortIndex: Int = 0,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.parentFolderID = parentFolderID
        self.originalParentFolderID = originalParentFolderID
        self.folderSortIndex = folderSortIndex
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
