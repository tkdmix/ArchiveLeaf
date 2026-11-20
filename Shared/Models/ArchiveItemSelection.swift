import Foundation

/// The resolved items and capabilities for one requested selection.
///
/// `items` must contain only results resolved from `requestedIDs`. Their order is preserved so a
/// caller can use the same ordering it presents in the UI. A missing, unexpected, or duplicate
/// resolved item makes the whole selection invalid; operations must not act on the partial result.
struct ArchiveItemSelection: Equatable, Sendable {
    let items: [ArchiveItem]
    let requestedIDs: Set<UUID>

    init(items: [ArchiveItem], requestedIDs: Set<UUID>) {
        self.items = items
        self.requestedIDs = requestedIDs
    }

    var requestedIDCount: Int { requestedIDs.count }

    var unknownIDs: Set<UUID> {
        requestedIDs.subtracting(ids)
    }

    var ids: [UUID] {
        items.map(\.id)
    }

    var folders: [ArchiveFolder] {
        items.compactMap { item in
            guard case .folder(let folder) = item else { return nil }
            return folder
        }
    }

    var files: [ArchiveFile] {
        items.compactMap { item in
            guard case .file(let file) = item else { return nil }
            return file
        }
    }

    var count: Int { requestedIDCount }
    var isEmpty: Bool { requestedIDs.isEmpty }

    var isValid: Bool {
        let resolvedIDs = Set(ids)
        return ids.count == resolvedIDs.count
            && resolvedIDs == requestedIDs
    }

    var isAllFiles: Bool {
        isValid && !isEmpty && files.count == count
    }

    var isSingle: Bool {
        isValid && count == 1
    }

    /// Whether everything chosen is in the archive, or everything chosen is in the Trash.
    ///
    /// The two are separate places with separate verbs, and no list shows both at once — so a
    /// selection that somehow held one of each can do nothing at all rather than half of it.
    var isAllInArchive: Bool {
        isValid && !isEmpty && items.allSatisfy { !$0.isTrashed }
    }

    var isAllInTrash: Bool {
        isValid && !isEmpty && items.allSatisfy(\.isTrashed)
    }

    var canMove: Bool { isAllInArchive }
    var canTrash: Bool { isAllInArchive }
    var canDropIntoFolder: Bool { isAllInArchive }

    var canTag: Bool { isAllFiles && isAllInArchive }
    var canFavorite: Bool { isAllFiles && isAllInArchive }
    var canShare: Bool { isAllFiles && isAllInArchive }

    var canRename: Bool { isSingle && isAllInArchive }

    /// Out of the Trash, back where it came from — and the one that cannot be undone.
    var canRestore: Bool { isAllInTrash }
    var canDeletePermanently: Bool { isAllInTrash }
}
