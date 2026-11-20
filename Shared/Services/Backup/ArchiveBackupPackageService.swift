import Foundation

protocol ArchiveBackupPackageServicing: Sendable {
    func exportArchive(to packageURL: URL) async throws -> ArchiveBackupManifest
    func inspectBackup(at packageURL: URL) async throws -> ArchiveBackupManifest
    func prepareRestore(from packageURL: URL) async throws -> ArchiveBackupRestorePlan
    func restore(_ plan: ArchiveBackupRestorePlan) async throws -> ArchiveBackupRestoreResult
}

/// A backup that has been read whole, checked, and found to fit an archive that was empty when it
/// was asked. Only `prepareRestore` can make one, which is what lets `restore` take the package as
/// already validated rather than having to wonder.
///
/// The type exists to stop the package being read twice. Validating it walks every asset and
/// digests every byte, and the reader is asked to confirm in between — so a `restore` that
/// re-validated what it was handed doubled the cost of every restore, in order to re-answer a
/// question about a local file that nothing had touched in the meantime.
struct ArchiveBackupRestorePlan: Sendable {
    let manifest: ArchiveBackupManifest
    let packageURL: URL

    /// Deliberately not the memberwise initializer: a plan that anyone could make would carry no
    /// evidence, and `restore` reads it as evidence.
    fileprivate init(manifest: ArchiveBackupManifest, packageURL: URL) {
        self.manifest = manifest
        self.packageURL = packageURL
    }
}

/// Carries what was written, not just how much. CloudKit answers queries from an index that lags
/// its own writes, so re-reading right after a restore can miss the records it just stored. The
/// caller already knows them exactly and should show these rather than ask again.
struct ArchiveBackupRestoreResult: Sendable {
    let restoredSnapshot: ArchiveSnapshot

    var restoredFolderCount: Int { restoredSnapshot.folders.count }
    var restoredFileCount: Int { restoredSnapshot.files.count }
    var restoredItemCount: Int { restoredFolderCount + restoredFileCount }
}

/// CloudKit cannot put a whole restore in one transaction, so a failure part-way through leaves
/// the records already written in place. Report that boundary rather than deleting them back out:
/// an automatic rollback would itself be a destructive operation that can fail.
///
/// The archive is no longer empty at this point, which is also the precondition for restoring, so
/// the message has to tell the user how to get back to a state where a retry is possible.
struct ArchiveBackupRestorePartialFailure: LocalizedError, Sendable {
    let restoredFolderCount: Int
    let restoredFileCount: Int
    let underlyingMessage: String

    var errorDescription: String? {
        String(
            localized:
                "Restore stopped after writing \(restoredFolderCount) folders and \(restoredFileCount) files. Those items are still in your archive, so restoring again needs an empty archive: use Delete My Archive… in Settings first. \(underlyingMessage)"
        )
    }
}

struct ArchiveBackupPackageService: ArchiveBackupPackageServicing {
    private static let maximumManifestSize: Int64 = 10 * 1_024 * 1_024

    private let repository: any ArchiveRepository
    private let coder: any ArchiveBackupManifestCoding
    private let hasher: any FileContentHashing

    init(
        repository: any ArchiveRepository,
        coder: any ArchiveBackupManifestCoding = JSONArchiveBackupManifestCoder(),
        hasher: any FileContentHashing = SHA256FileContentHasher()
    ) {
        self.repository = repository
        self.coder = coder
        self.hasher = hasher
    }

    func exportArchive(to packageURL: URL) async throws -> ArchiveBackupManifest {
        try validatePackageDestination(packageURL)
        let snapshot = try await repository.fetchSnapshot()
        let manifest = ArchiveBackupManifest(
            folders: snapshot.folders,
            files: snapshot.files.map { ArchiveBackupFileEntry(file: $0) },
            tags: snapshot.tags
        )
        let temporaryURL = packageURL.deletingLastPathComponent()
            .appendingPathComponent(".ArchiveLeafBackup-\(UUID().uuidString)", isDirectory: true)

        do {
            let assetsURL = temporaryURL.appendingPathComponent(
                ArchiveBackupPackage.assetsDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

            // Sizes here, digests once at the end. Digesting the source as well as the copy read
            // the whole archive twice to prove one thing: a copy whose digest matches the hash
            // recorded for the file says both that the source was intact and that the copy is
            // faithful, because a copy of corrupt bytes fails the same comparison. The size is
            // checked here anyway — it comes from the file's metadata, so it costs nothing, and it
            // turns a mismatched source back before its bytes are copied at all.
            for entry in manifest.files {
                try Task.checkCancellation()
                let sourceURL = try await repository.fileContentURL(for: entry.file.id)
                try validateRegularFile(sourceURL)
                try validateSize(of: sourceURL, expected: entry.file.fileSize, named: entry.file.sidebarDisplayName)
                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: temporaryURL.appendingPathComponent(entry.assetRelativePath)
                )
            }

            let manifestData = try coder.encode(manifest)
            try manifestData.write(
                to: temporaryURL.appendingPathComponent(ArchiveBackupPackage.manifestFileName),
                options: Data.WritingOptions.atomic
            )
            _ = try await inspectBackup(at: temporaryURL, requiresPackageExtension: false)
            try FileManager.default.moveItem(at: temporaryURL, to: packageURL)
            return manifest
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func inspectBackup(at packageURL: URL) async throws -> ArchiveBackupManifest {
        try await inspectBackup(at: packageURL, requiresPackageExtension: true)
    }

    func prepareRestore(from packageURL: URL) async throws -> ArchiveBackupRestorePlan {
        let manifest = try await inspectBackup(at: packageURL)
        try await requireEmptyArchive()
        return ArchiveBackupRestorePlan(manifest: manifest, packageURL: packageURL)
    }

    func restore(_ plan: ArchiveBackupRestorePlan) async throws -> ArchiveBackupRestoreResult {
        // Asked again, and this alone. The archive is somewhere another device can write, and the
        // reader has been sitting on a confirmation since the plan was made, so the one thing that
        // can have changed is checked again. It is also the cheap half: an archive that is still
        // empty answers every one of these reads with nothing.
        try await requireEmptyArchive()
        let manifest = plan.manifest
        let packageURL = plan.packageURL
        // Only the folders need remembering: they are already written by the time the files can
        // fail, and every other boundary is either nothing yet or reported by the write itself.
        var restoredFolderCount = 0

        // Each kind in one piece of work rather than one per record. The archive has just been
        // found empty, so none of these need reading before they are written — which was half of
        // every round trip a restore made, and the half whose answer was known before it was asked.
        //
        // Before the files: a file arriving with a tag id should find the tag already there.
        do {
            try await repository.createInEmptyArchive(tags: manifest.tags)
        } catch {
            throw restoreStopped(folders: 0, files: 0, error)
        }
        do {
            try await repository.createInEmptyArchive(folders: foldersParentsFirst(manifest.folders))
            restoredFolderCount = manifest.folders.count
        } catch {
            throw restoreStopped(folders: writtenCount(of: error), files: 0, error)
        }
        do {
            try await repository.createInEmptyArchive(files: manifest.files.map { entry in
                ArchiveFileAsset(
                    file: entry.file,
                    assetURL: packageURL.appendingPathComponent(entry.assetRelativePath)
                )
            })
        } catch {
            throw restoreStopped(
                folders: restoredFolderCount,
                files: writtenCount(of: error),
                error
            )
        }

        return ArchiveBackupRestoreResult(
            restoredSnapshot: ArchiveSnapshot(
                folders: manifest.folders,
                files: manifest.files.map(\.file),
                tags: manifest.tags
            )
        )
    }

    /// Unwraps what the repository reports so the reader is told the archive's own numbers rather
    /// than the shape the write happened to take.
    private func writtenCount(of error: any Error) -> Int {
        (error as? ArchivePartialWriteFailure)?.writtenCount ?? 0
    }

    private func restoreStopped(
        folders: Int,
        files: Int,
        _ error: any Error
    ) -> ArchiveBackupRestorePartialFailure {
        let reason = (error as? ArchivePartialWriteFailure)?.underlying ?? error
        return ArchiveBackupRestorePartialFailure(
            restoredFolderCount: folders,
            restoredFileCount: files,
            underlyingMessage: reason.localizedDescription
        )
    }

    private func requireEmptyArchive() async throws {
        async let snapshot = repository.fetchSnapshot()
        async let trashedFiles = repository.fetchTrashedFiles()
        async let trashedFolders = repository.fetchTrashedFolders()
        let current = try await (snapshot, trashedFiles, trashedFolders)
        guard current.0.folders.isEmpty,
              current.0.files.isEmpty,
              current.1.isEmpty,
              current.2.isEmpty else {
            throw ArchiveBackupPackageError.restoreRequiresEmptyArchive
        }
    }

    /// A folder has to exist before anything can point at it as a parent. Validation has already
    /// rejected cycles and missing parents, so a repeated sweep resolves the whole hierarchy.
    private func foldersParentsFirst(_ folders: [ArchiveFolder]) -> [ArchiveFolder] {
        var remaining = folders
        var writtenIDs: Set<UUID> = []
        var ordered: [ArchiveFolder] = []

        while !remaining.isEmpty {
            let ready = remaining.filter { folder in
                guard let parentID = folder.parentFolderID else { return true }
                return writtenIDs.contains(parentID)
            }
            guard !ready.isEmpty else { break }
            ordered.append(contentsOf: ready)
            writtenIDs.formUnion(ready.map(\.id))
            remaining.removeAll { writtenIDs.contains($0.id) }
        }
        return ordered + remaining
    }

    private func inspectBackup(
        at packageURL: URL,
        requiresPackageExtension: Bool
    ) async throws -> ArchiveBackupManifest {
        if requiresPackageExtension,
           packageURL.pathExtension.caseInsensitiveCompare(ArchiveBackupPackage.pathExtension) != .orderedSame {
            throw ArchiveBackupPackageError.invalidPackage
        }
        try validateDirectory(packageURL)

        let manifestURL = packageURL.appendingPathComponent(ArchiveBackupPackage.manifestFileName)
        try validateRegularFile(manifestURL)
        let manifestSize = try fileSize(at: manifestURL)
        guard manifestSize <= Self.maximumManifestSize else {
            throw ArchiveBackupPackageError.manifestTooLarge
        }
        let manifest = try coder.decode(Data(contentsOf: manifestURL, options: .mappedIfSafe))

        for entry in manifest.files {
            try Task.checkCancellation()
            let assetURL = packageURL.appendingPathComponent(entry.assetRelativePath)
            try validateRegularFile(assetURL)
            try validateSize(of: assetURL, expected: entry.file.fileSize, named: entry.file.sidebarDisplayName)
            try await validateHash(
                of: assetURL,
                expected: entry.file.contentHash,
                named: entry.file.sidebarDisplayName
            )
        }
        return manifest
    }

    private func validatePackageDestination(_ url: URL) throws {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare(ArchiveBackupPackage.pathExtension) == .orderedSame,
              !FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveBackupPackageError.invalidDestination
        }
    }

    private func validateDirectory(_ url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw ArchiveBackupPackageError.invalidPackage
        }
    }

    private func validateRegularFile(_ url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw ArchiveBackupPackageError.missingOrUnsafeAsset
        }
    }

    private func validateSize(of url: URL, expected: Int64, named name: String) throws {
        guard try fileSize(at: url) == expected else {
            throw ArchiveBackupPackageError.assetSizeMismatch(name)
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw ArchiveBackupPackageError.missingOrUnsafeAsset
        }
        return Int64(size)
    }

    private func validateHash(of url: URL, expected: String, named name: String) async throws {
        let actual = try await hasher.sha256(for: url)
        guard !expected.isEmpty,
              actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw ArchiveBackupPackageError.assetHashMismatch(name)
        }
    }
}

enum ArchiveBackupPackageError: LocalizedError, Equatable, Sendable {
    case invalidDestination
    case invalidPackage
    case manifestTooLarge
    case missingOrUnsafeAsset
    case assetSizeMismatch(String)
    case assetHashMismatch(String)
    case restoreRequiresEmptyArchive

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            String(localized: "Choose a new file ending in .albak.")
        case .invalidPackage:
            String(localized: "This is not a valid ArchiveLeaf backup package.")
        case .manifestTooLarge:
            String(localized: "The backup manifest is too large.")
        case .missingOrUnsafeAsset:
            String(localized: "The backup contains a missing or unsafe file.")
        // One bad record stops the whole operation, so the message has to say which one.
        case .assetSizeMismatch(let name):
            String(localized: "“\(name)” does not match its recorded size.")
        case .assetHashMismatch(let name):
            String(localized: "“\(name)” does not match its recorded checksum.")
        // Deliberately no shortcut to the deletion control: naming it is help, offering a one-tap
        // path from a blocked restore into an irreversible wipe is not.
        case .restoreRequiresEmptyArchive:
            String(
                localized:
                    "Restore needs an empty Archive, and yours still holds items. Emptying Trash is part of that. To start over from this backup, use Delete My Archive… above first."
            )
        }
    }
}
