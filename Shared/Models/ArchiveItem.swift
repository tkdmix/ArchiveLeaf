import Foundation

enum ArchiveItem: Identifiable, Hashable, Sendable {
    case folder(ArchiveFolder)
    case file(ArchiveFile)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .file(let file): file.id
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    /// Whether this item is in the Trash. What can be done to it turns on this: a discarded item
    /// takes restoring and permanent deletion, and an item in the archive takes everything else.
    var isTrashed: Bool {
        switch self {
        case .folder(let folder): folder.isTrashed
        case .file(let file): file.isTrashed
        }
    }

    var displayName: String {
        switch self {
        case .folder(let folder): folder.name
        case .file(let file): file.displayName
        }
    }

    /// The name as a list shows it, which for a file keeps its extension. What a reader scans for
    /// is what is on the row, so it is also what a list orders by — the archive's own file lists
    /// have always sorted on this.
    var listedName: String {
        switch self {
        case .folder(let folder): folder.name
        case .file(let file): file.sidebarDisplayName
        }
    }
}
