import Foundation

protocol ArchiveBackupManifestValidating: Sendable {
    func validate(_ manifest: ArchiveBackupManifest) throws
}

struct ArchiveBackupManifestValidator: ArchiveBackupManifestValidating {
    func validate(_ manifest: ArchiveBackupManifest) throws {
        guard manifest.format == ArchiveBackupManifest.formatIdentifier else {
            throw ArchiveBackupValidationError.unsupportedFormat
        }
        guard manifest.schemaVersion == ArchiveBackupManifest.currentSchemaVersion else {
            throw ArchiveBackupValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        let folderIDs = try uniqueIDs(manifest.folders.map(\.id))
        let fileIDs = try uniqueIDs(manifest.files.map(\.file.id))
        guard folderIDs.isDisjoint(with: fileIDs) else {
            throw ArchiveBackupValidationError.duplicateIdentifier
        }

        for folder in manifest.folders {
            guard !folder.isTrashed else {
                throw ArchiveBackupValidationError.trashedItem(folder.id)
            }
            if let parentID = folder.parentFolderID, !folderIDs.contains(parentID) {
                throw ArchiveBackupValidationError.missingParent(folder.id)
            }
            if folder.parentFolderID == folder.id {
                throw ArchiveBackupValidationError.folderCycle(folder.id)
            }
            try validateFolderAncestry(from: folder, folders: manifest.folders)
        }

        for entry in manifest.files {
            guard !entry.file.isTrashed else {
                throw ArchiveBackupValidationError.trashedItem(entry.file.id)
            }
            if let parentID = entry.file.parentFolderID, !folderIDs.contains(parentID) {
                throw ArchiveBackupValidationError.missingParent(entry.file.id)
            }
            guard entry.file.importState == .completed else {
                throw ArchiveBackupValidationError.incompleteFile(entry.file.id)
            }
            guard entry.file.fileSize >= 0 else {
                throw ArchiveBackupValidationError.invalidFileSize(entry.file.id)
            }
            guard entry.assetRelativePath == ArchiveBackupPackage.assetRelativePath(for: entry.file.id) else {
                throw ArchiveBackupValidationError.invalidAssetPath(entry.file.id)
            }
        }
    }

    private func uniqueIDs(_ ids: [UUID]) throws -> Set<UUID> {
        let unique = Set(ids)
        guard unique.count == ids.count else {
            throw ArchiveBackupValidationError.duplicateIdentifier
        }
        return unique
    }

    private func validateFolderAncestry(
        from folder: ArchiveFolder,
        folders: [ArchiveFolder]
    ) throws {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var visited = Set([folder.id])
        var parentID = folder.parentFolderID

        while let currentID = parentID {
            guard visited.insert(currentID).inserted else {
                throw ArchiveBackupValidationError.folderCycle(folder.id)
            }
            parentID = foldersByID[currentID]?.parentFolderID
        }
    }
}

enum ArchiveBackupValidationError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier
    case missingParent(UUID)
    case folderCycle(UUID)
    case incompleteFile(UUID)
    case invalidFileSize(UUID)
    case invalidAssetPath(UUID)
    case trashedItem(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "This is not an ArchiveLeaf backup."
        case .unsupportedSchemaVersion(let version):
            "Backup version \(version) is not supported."
        case .duplicateIdentifier:
            "The backup contains duplicate item identifiers."
        case .missingParent:
            "The backup contains an item whose parent folder is missing."
        case .folderCycle:
            "The backup contains a circular folder hierarchy."
        case .incompleteFile:
            "The backup contains an incomplete file."
        case .invalidFileSize:
            "The backup contains an invalid file size."
        case .invalidAssetPath:
            "The backup contains an invalid asset path."
        case .trashedItem:
            "The backup contains an item from Trash."
        }
    }
}
