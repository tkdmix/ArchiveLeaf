import Foundation

/// UI-facing boundary for the CloudKit-backed archive metadata and assets.
protocol ArchiveRepository: ArchiveTrashPurging, Sendable {
    /// Everything a launch needs, from one read.
    ///
    /// The shelf and the Trash are the same records: what is in the Trash is worked out from the
    /// same folders and files that the shelf is worked out from, by hiding instead of showing. Asked
    /// for separately, they were the same records fetched again — a launch read every file record
    /// three times and every folder record three times, and the two extra rounds could only ever
    /// arrive at what the first already held.
    func fetchContents() async throws -> ArchiveContents
    func fetchSnapshot() async throws -> ArchiveSnapshot
    func fetchTrashedFiles() async throws -> [ArchiveFile]
    func fetchTrashedFolders() async throws -> [ArchiveFolder]
    /// For each trashed folder, how many items sit inside it.
    ///
    /// A folder in the Trash listed only its name, so a restore brought back things that were never
    /// shown and a permanent delete took them without saying so.
    func fetchTrashedFolderItemCounts() async throws -> [UUID: Int]
    func fileContentURL(for fileID: UUID) async throws -> URL
    func save(folder: ArchiveFolder) async throws
    func save(file: ArchiveFile) async throws
    func save(file: ArchiveFile, assetURL: URL) async throws
    /// Saves many files as one piece of work, and says which of them did not make it.
    ///
    /// The one-at-a-time call is a round trip to read the record and another to write it. Twenty
    /// files is forty round trips waited on in a row — measured against the real archive, 549 ms
    /// each and eleven seconds for twenty stars. This reads them all at once and writes them all at
    /// once, so the cost stops following the number of items.
    ///
    /// - Returns: the files that could not be saved, each with the reason. An empty result means
    ///   every file was saved. Partial failure is a real outcome rather than an error: what did
    ///   save is saved, and the caller decides what to say about the rest.
    func save(files: [ArchiveFile]) async throws -> [UUID: any Error]
    /// Writes newly imported files, payload and all, without reading anything first.
    ///
    /// An import has just made these identifiers, so no record can exist under them: the fetch an
    /// ordinary save performs in order to change what is already there is, here, a round trip spent
    /// learning that a brand-new UUID is unused. They go in batches for the same reason a restore
    /// does — the cost stops following the file count.
    ///
    /// - Returns: every file that did not land, with the reason. Files never attempted, because a
    ///   batch before them failed or the work was cancelled, are reported as
    ///   `ArchiveWriteNotAttempted` rather than left out — a caller counting what is missing would
    ///   otherwise count them as written.
    func create(files: [ArchiveFileAsset]) async throws -> [UUID: any Error]
    /// Writes folders known not to exist yet, parents before children, in the order given.
    ///
    /// One intention rather than a list of them: a folder that cannot be written is a folder its
    /// children cannot go in, so this stops at the first refusal and says how far it got.
    func create(folders: [ArchiveFolder]) async throws
    func save(tag: ArchiveTag) async throws
    /// Removes the tag itself. Files carrying it are the caller's to update.
    func delete(tag: ArchiveTag) async throws

    /// Writes records that are known not to exist yet.
    ///
    /// This is the state a restore begins from, having just established that the archive holds
    /// nothing. Two things separate it from `save(...)`, and neither is the number of records.
    /// Nothing is read first: an ordinary save fetches the record in order to change what is
    /// already there, and during a restore every one of those fetches is a round trip spent
    /// confirming that an empty archive is empty — half of the whole cost, and every answer known
    /// in advance. And the writes go in batches, so the cost stops following the item count.
    ///
    /// Stops at the first refusal instead of carrying on. A restore is one intention rather than a
    /// list of separate ones, so unlike `save(files:)` there is no per-item failure to report — but
    /// the caller still has to say how far it got, so the failure arrives as
    /// `ArchivePartialWriteFailure` carrying the number already written.
    func createInEmptyArchive(tags: [ArchiveTag]) async throws
    /// Parents before children: the order given is the order written.
    func createInEmptyArchive(folders: [ArchiveFolder]) async throws
    func createInEmptyArchive(files: [ArchiveFileAsset]) async throws
}

/// The archive as one answer: what is on the shelf, and what is in the Trash.
struct ArchiveContents: Sendable {
    let snapshot: ArchiveSnapshot
    let trashedFiles: [ArchiveFile]
    let trashedFolders: [ArchiveFolder]
    let trashedFolderItemCounts: [UUID: Int]
}

/// A file and the payload stored with it.
struct ArchiveFileAsset: Sendable {
    let file: ArchiveFile
    let assetURL: URL

    init(file: ArchiveFile, assetURL: URL) {
        self.file = file
        self.assetURL = assetURL
    }
}

/// How far a write that stops at the first refusal had already got.
///
/// Records already written stay where they are. Undoing them would itself be a destructive
/// operation that can fail, so the boundary is reported rather than erased.
struct ArchivePartialWriteFailure: Error, Sendable {
    let writtenCount: Int
    let underlying: any Error
}

/// A write that was never sent, because an earlier one failed or the work was cancelled.
///
/// Reported rather than silently absent: "it was not tried" and "it was refused" are different
/// things to be told, and the reader can act on the first by trying again.
struct ArchiveWriteNotAttempted: LocalizedError, Sendable {
    var errorDescription: String? {
        String(localized: "Not attempted, because an earlier item could not be added.")
    }
}


extension ArchiveRepository {
    /// One at a time, which is the whole cost where a write does not leave the process. CloudKit
    /// provides its own: there a write is a round trip, and twenty of them are twenty waits.
    func save(files: [ArchiveFile]) async throws -> [UUID: any Error] {
        var failures: [UUID: any Error] = [:]
        for file in files {
            do {
                try await save(file: file)
            } catch {
                failures[file.id] = error
            }
        }
        return failures
    }

    /// One at a time, which is the whole cost where a write does not leave the process. CloudKit
    /// provides its own, where the saving is in the round trips.
    func create(files: [ArchiveFileAsset]) async throws -> [UUID: any Error] {
        var failures: [UUID: any Error] = [:]
        var stopped = false
        for entry in files {
            guard !stopped else {
                failures[entry.file.id] = ArchiveWriteNotAttempted()
                continue
            }
            do {
                try Task.checkCancellation()
                try await save(file: entry.file, assetURL: entry.assetURL)
            } catch {
                failures[entry.file.id] = error
                stopped = true
            }
        }
        return failures
    }

    /// Nothing, for a repository that does not keep a hierarchy — the count is only ever shown, so
    /// its absence costs a line of a row rather than any behaviour.
    func fetchTrashedFolderItemCounts() async throws -> [UUID: Int] { [:] }

    /// Asked four ways, which is the honest cost where a read does not leave the process. A
    /// repository that answers from memory has nothing to gain by answering once instead of four
    /// times; CloudKit provides its own, because there each of these is a round trip.
    func fetchContents() async throws -> ArchiveContents {
        async let snapshot = fetchSnapshot()
        async let trashedFiles = fetchTrashedFiles()
        async let trashedFolders = fetchTrashedFolders()
        async let counts = fetchTrashedFolderItemCounts()
        return ArchiveContents(
            snapshot: try await snapshot,
            trashedFiles: try await trashedFiles,
            trashedFolders: try await trashedFolders,
            trashedFolderItemCounts: try await counts
        )
    }

    /// One at a time, which is the whole cost where a write does not leave the process. The saving
    /// is in the round trips, and a repository that makes none has nothing to save. CloudKit
    /// provides its own.
    func createInEmptyArchive(tags: [ArchiveTag]) async throws {
        try await writingInTurn(tags) { try await save(tag: $0) }
    }

    func create(folders: [ArchiveFolder]) async throws {
        try await writingInTurn(folders) { try await save(folder: $0) }
    }

    /// A restore's folders are new records like any other, so it asks the same way.
    func createInEmptyArchive(folders: [ArchiveFolder]) async throws {
        try await create(folders: folders)
    }

    func createInEmptyArchive(files: [ArchiveFileAsset]) async throws {
        try await writingInTurn(files) { try await save(file: $0.file, assetURL: $0.assetURL) }
    }

    private func writingInTurn<Item>(
        _ items: [Item],
        _ write: (Item) async throws -> Void
    ) async throws {
        var written = 0
        for item in items {
            do {
                try Task.checkCancellation()
                try await write(item)
                written += 1
            } catch {
                throw ArchivePartialWriteFailure(writtenCount: written, underlying: error)
            }
        }
    }
}
