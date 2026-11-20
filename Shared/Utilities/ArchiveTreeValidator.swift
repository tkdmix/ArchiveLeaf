import Foundation

enum ArchiveTreeValidator {
    static func validate(folder: ArchiveFolder, in snapshot: ArchiveSnapshot) throws {
        try validateParentExists(folder.parentFolderID, in: snapshot)
        try validateName(
            folder.name,
            parentFolderID: folder.parentFolderID,
            excluding: folder.id,
            in: snapshot
        )
        try validateFolderPlacement(folder, in: snapshot)
    }

    static func validate(file: ArchiveFile, in snapshot: ArchiveSnapshot) throws {
        try validateParentExists(file.parentFolderID, in: snapshot)
        try validateName(
            file.displayName,
            parentFolderID: file.parentFolderID,
            excluding: file.id,
            in: snapshot
        )
    }

    private static func validateParentExists(_ parentID: UUID?, in snapshot: ArchiveSnapshot) throws {
        guard let parentID else { return }
        guard snapshot.folders.contains(where: { $0.id == parentID && !$0.isTrashed }) else {
            throw ArchiveValidationError.missingParent
        }
    }

    private static func validateName(
        _ name: String,
        parentFolderID: UUID?,
        excluding itemID: UUID,
        in snapshot: ArchiveSnapshot
    ) throws {
        let normalizedName = ArchiveRules.normalizedName(name)
        guard !normalizedName.isEmpty else {
            throw ArchiveValidationError.emptyName
        }

        let folderCollision = snapshot.folders.contains {
            $0.id != itemID && !$0.isTrashed && $0.parentFolderID == parentFolderID
                && ArchiveRules.normalizedName($0.name) == normalizedName
        }
        let fileCollision = snapshot.files.contains {
            $0.id != itemID && !$0.isTrashed && $0.parentFolderID == parentFolderID
                && ArchiveRules.normalizedName($0.displayName) == normalizedName
        }

        guard !folderCollision && !fileCollision else {
            throw ArchiveValidationError.duplicateName
        }
    }

    private static func validateFolderPlacement(
        _ folder: ArchiveFolder,
        in snapshot: ArchiveSnapshot
    ) throws {
        guard folder.parentFolderID != folder.id else {
            throw ArchiveValidationError.cyclicFolderReference
        }

        let foldersByID = Dictionary(uniqueKeysWithValues: snapshot.folders.map { ($0.id, $0) })
        var ancestorID = folder.parentFolderID
        var visited = Set<UUID>()
        while let currentID = ancestorID {
            guard visited.insert(currentID).inserted, currentID != folder.id else {
                throw ArchiveValidationError.cyclicFolderReference
            }
            guard let current = foldersByID[currentID] else {
                throw ArchiveValidationError.missingParent
            }
            ancestorID = current.parentFolderID
        }
    }
}
