import Foundation

actor InMemoryArchiveRepository: ArchiveRepository, DuplicateFileLookingUp {
    private var foldersByID: [UUID: ArchiveFolder]
    private var filesByID: [UUID: ArchiveFile]
    private var assetDataByFileID: [UUID: Data]
    private var tagsByID: [UUID: ArchiveTag]

    init(
        folders: [ArchiveFolder] = [],
        files: [ArchiveFile] = [],
        tags: [ArchiveTag] = [],
        assetDataByFileID: [UUID: Data] = [:]
    ) {
        tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        self.assetDataByFileID = assetDataByFileID
    }

    func fetchSnapshot() -> ArchiveSnapshot {
        let snapshot = ArchiveTrashFilter.visibleSnapshot(
            folders: Array(foldersByID.values),
            files: Array(filesByID.values)
        )
        return ArchiveSnapshot(
            folders: snapshot.folders.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            files: snapshot.files.sorted { $0.importedAt < $1.importedAt },
            tags: tagsByID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    func fetchTrashedFiles() -> [ArchiveFile] {
        filesByID.values
            .filter { $0.isTrashed && $0.importState == .completed }
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    func fetchTrashedFolders() -> [ArchiveFolder] {
        foldersByID.values
            .filter(\.isTrashed)
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    func fetchTrashedFolderItemCounts() -> [UUID: Int] {
        ArchiveTrashFilter.itemCountsUnderTrashedFolders(
            folders: Array(foldersByID.values),
            files: Array(filesByID.values)
        )
    }

    func fileContentURL(for fileID: UUID) throws -> URL {
        guard let file = filesByID[fileID] else {
            throw ArchiveValidationError.missingParent
        }
        guard let data = assetDataByFileID[fileID] else {
            throw ArchiveLeafError.unreadableFile
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(file.id.uuidString)
            .appendingPathExtension(file.originalExtension ?? "data")
        try data.write(to: url, options: .atomic)
        return url
    }

    func save(folder: ArchiveFolder) throws {
        let snapshot = completeSnapshot()
        if !folder.isTrashed {
            try ArchiveTreeValidator.validate(folder: folder, in: snapshot)
        }
        foldersByID[folder.id] = folder
    }

    func save(file: ArchiveFile) throws {
        let snapshot = completeSnapshot()
        if !file.isTrashed {
            try ArchiveTreeValidator.validate(file: file, in: snapshot)
        }
        filesByID[file.id] = file
    }

    func save(file: ArchiveFile, assetURL: URL) throws {
        assetDataByFileID[file.id] = try Data(contentsOf: assetURL)
        try save(file: file)
    }

    func files(matchingContentHashes hashes: Set<String>) -> [String: ArchiveFile] {
        var matches: [String: ArchiveFile] = [:]
        for file in filesByID.values where file.importState == .completed {
            let hash = file.contentHash.lowercased()
            guard hashes.contains(hash), matches[hash] == nil else { continue }
            matches[hash] = file
        }
        return matches
    }

    func save(tag: ArchiveTag) {
        tagsByID[tag.id] = tag
    }

    func delete(tag: ArchiveTag) {
        tagsByID[tag.id] = nil
    }

    private func completeSnapshot() -> ArchiveSnapshot {
        ArchiveSnapshot(
            folders: Array(foldersByID.values),
            files: Array(filesByID.values)
        )
    }
}

extension InMemoryArchiveRepository: ArchiveResetting {
    func resetArchive() -> ArchiveResetResult {
        let result = ArchiveResetResult(
            deletedFolderCount: foldersByID.count,
            deletedFileCount: filesByID.count
        )
        foldersByID.removeAll()
        filesByID.removeAll()
        assetDataByFileID.removeAll()
        tagsByID.removeAll()
        return result
    }
}

extension InMemoryArchiveRepository: IncompleteImportPurging {
    func fetchIncompleteImportCount() -> Int {
        incompleteImportFileIDs().count
    }

    func removeIncompleteImports() -> IncompleteImportPurgeResult {
        let fileIDs = incompleteImportFileIDs()
        fileIDs.forEach {
            filesByID[$0] = nil
            assetDataByFileID[$0] = nil
        }
        return IncompleteImportPurgeResult(deletedFileCount: fileIDs.count)
    }

    private func incompleteImportFileIDs() -> [UUID] {
        filesByID.values
            .filter { $0.importState != .completed }
            .map(\.id)
    }
}

extension InMemoryArchiveRepository {
    func permanentlyDelete(_ item: ArchiveItem) async throws -> ArchiveDeletionResult {
        switch item {
        case .file(let file):
            guard filesByID[file.id]?.isTrashed == true else {
                throw ArchiveValidationError.missingParent
            }
            filesByID[file.id] = nil
            assetDataByFileID[file.id] = nil
            return ArchiveDeletionResult(deletedFolderCount: 0, deletedFileCount: 1)

        case .folder(let folder):
            guard foldersByID[folder.id]?.isTrashed == true else {
                throw ArchiveValidationError.missingParent
            }
            let subtreeIDs = ArchiveTrashFilter.subtreeFolderIDs(
                rootedAt: [folder.id],
                folders: Array(foldersByID.values)
            )
            let fileIDs = filesByID.values
                .filter { $0.parentFolderID.map(subtreeIDs.contains) ?? false }
                .map(\.id)
            fileIDs.forEach {
                filesByID[$0] = nil
                assetDataByFileID[$0] = nil
            }
            subtreeIDs.forEach { foldersByID[$0] = nil }
            return ArchiveDeletionResult(
                deletedFolderCount: subtreeIDs.count,
                deletedFileCount: fileIDs.count
            )
        }
    }

    func emptyTrash() async throws -> ArchiveDeletionResult {
        let trashedRootIDs = Set(foldersByID.values.filter(\.isTrashed).map(\.id))
        let folderIDs = ArchiveTrashFilter.subtreeFolderIDs(
            rootedAt: trashedRootIDs,
            folders: Array(foldersByID.values)
        )
        let fileIDs = filesByID.values
            .filter {
                $0.isTrashed || ($0.parentFolderID.map(folderIDs.contains) ?? false)
            }
            .map(\.id)
        fileIDs.forEach {
            filesByID[$0] = nil
            assetDataByFileID[$0] = nil
        }
        folderIDs.forEach { foldersByID[$0] = nil }
        return ArchiveDeletionResult(
            deletedFolderCount: folderIDs.count,
            deletedFileCount: fileIDs.count
        )
    }
}
