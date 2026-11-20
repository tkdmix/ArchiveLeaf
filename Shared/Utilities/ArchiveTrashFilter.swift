import Foundation

enum ArchiveTrashFilter {
    static func visibleSnapshot(
        folders: [ArchiveFolder],
        files: [ArchiveFile]
    ) -> ArchiveSnapshot {
        let hiddenFolderIDs = subtreeFolderIDs(
            rootedAt: Set(folders.filter(\.isTrashed).map(\.id)),
            folders: folders
        )
        return ArchiveSnapshot(
            folders: folders.filter { !$0.isTrashed && !hiddenFolderIDs.contains($0.id) },
            files: files.filter {
                !$0.isTrashed
                    && $0.importState == .completed
                    && !($0.parentFolderID.map(hiddenFolderIDs.contains) ?? false)
            }
        )
    }

    /// How many items sit under each trashed folder, counting the folders and files at every depth
    /// but not the trashed folder itself.
    static func itemCountsUnderTrashedFolders(
        folders: [ArchiveFolder],
        files: [ArchiveFile]
    ) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for root in folders where root.isTrashed {
            let inside = subtreeFolderIDs(rootedAt: [root.id], folders: folders)
                .subtracting([root.id])
            let filesInside = files.filter { file in
                guard file.importState == .completed, !file.isTrashed else { return false }
                guard let parent = file.parentFolderID else { return false }
                return parent == root.id || inside.contains(parent)
            }
            counts[root.id] = inside.count + filesInside.count
        }
        return counts
    }

    /// Takes anything that knows who it is and where it sits, rather than a whole folder. Deciding
    /// what a delete reaches needs those two facts and nothing else, and reading a record's name and
    /// dates in order to throw them away is what made emptying the Trash cost the size of the
    /// archive rather than the size of the Trash.
    static func subtreeFolderIDs<Folder: ArchivePlaced>(
        rootedAt rootIDs: Set<UUID>,
        folders: [Folder]
    ) -> Set<UUID> {
        var result = rootIDs
        var didAddFolder = true
        while didAddFolder {
            didAddFolder = false
            for folder in folders where !result.contains(folder.id) {
                if let parentID = folder.parentFolderID, result.contains(parentID) {
                    result.insert(folder.id)
                    didAddFolder = true
                }
            }
        }
        return result
    }
}

/// Who a thing is and which folder it sits in — the whole of what the hierarchy is made of.
///
/// Named separately so that a projection carrying only these two fields can answer the same
/// questions as a fully read record, which is what lets a delete enumerate identity instead of
/// content.
protocol ArchivePlaced {
    var id: UUID { get }
    var parentFolderID: UUID? { get }
}

extension ArchiveFolder: ArchivePlaced {}
