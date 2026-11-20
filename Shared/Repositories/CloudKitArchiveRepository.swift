@preconcurrency import CloudKit
import Foundation

actor CloudKitArchiveRepository: ArchiveRepository, DuplicateFileLookingUp {
    private let container: CKContainer
    private let database: CKDatabase
    private var recentCompletedFilesByHash: [String: ArchiveFile] = [:]
    /// The write under way on each record, so the next one can wait for it.
    private var writesInFlight: [CKRecord.ID: Task<Void, Never>] = [:]

    init(containerIdentifier: String = CloudKitSchema.containerIdentifier) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    /// One read of the folders, one of the files, one of the tags. Everything else on this screen —
    /// the shelf, the Trash, and the count beside each discarded folder — is worked out from those
    /// three, because it always was: the difference is only whether the records are fetched again
    /// to do it.
    func fetchContents() async throws -> ArchiveContents {
        try await requireAvailableAccount()
        async let folderRecords = fetchAllRecords(ofType: CloudKitSchema.RecordType.folder)
        async let fileRecords = fetchAllRecords(
            ofType: CloudKitSchema.RecordType.file,
            desiredKeys: CloudKitSchema.fileMetadataFields
        )

        async let tagRecords = fetchTagRecords()
        let allFolders = try await folderRecords.map(CloudKitRecordMapper.folder(from:))
        let allFiles = try await fileRecords.map(CloudKitRecordMapper.file(from:))
        let allTags = try await tagRecords.map(CloudKitRecordMapper.tag(from:))
        let visible = ArchiveTrashFilter.visibleSnapshot(folders: allFolders, files: allFiles)
        // Discarded files count as duplicates too — the reader is told to restore the one they
        // already have rather than bring in a second copy — so the Trash goes in here as well.
        // Without it every import of something previously discarded went to the service to ask.
        for file in allFiles where file.importState == .completed {
            recentCompletedFilesByHash[file.contentHash.lowercased()] = file
        }
        return ArchiveContents(
            snapshot: ArchiveSnapshot(folders: visible.folders, files: visible.files, tags: allTags),
            trashedFiles: allFiles
                .filter { $0.isTrashed && $0.importState == .completed }
                .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) },
            trashedFolders: allFolders
                .filter(\.isTrashed)
                .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) },
            trashedFolderItemCounts: ArchiveTrashFilter.itemCountsUnderTrashedFolders(
                folders: allFolders,
                files: allFiles
            )
        )
    }

    func fetchSnapshot() async throws -> ArchiveSnapshot {
        try await fetchContents().snapshot
    }

    func fetchTrashedFiles() async throws -> [ArchiveFile] {
        try await requireAvailableAccount()
        let records = try await fetchAllRecords(
            ofType: CloudKitSchema.RecordType.file,
            desiredKeys: CloudKitSchema.fileMetadataFields
        )
        return try records
            .map(CloudKitRecordMapper.file(from:))
            .filter { $0.isTrashed && $0.importState == .completed }
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    func fetchTrashedFolders() async throws -> [ArchiveFolder] {
        try await requireAvailableAccount()
        let records = try await fetchAllRecords(ofType: CloudKitSchema.RecordType.folder)
        return try records
            .map(CloudKitRecordMapper.folder(from:))
            .filter(\.isTrashed)
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    func fetchTrashedFolderItemCounts() async throws -> [UUID: Int] {
        try await requireAvailableAccount()
        async let folderRecords = fetchAllRecords(ofType: CloudKitSchema.RecordType.folder)
        async let fileRecords = fetchAllRecords(
            ofType: CloudKitSchema.RecordType.file,
            desiredKeys: CloudKitSchema.fileMetadataFields
        )
        let folders = try await folderRecords.map(CloudKitRecordMapper.folder(from:))
        let files = try await fileRecords.map(CloudKitRecordMapper.file(from:))
        return ArchiveTrashFilter.itemCountsUnderTrashedFolders(folders: folders, files: files)
    }

    /// No tags where the archive cannot answer for them.
    ///
    /// Two ways that happens, and neither is a reason to lose the archive. An archive that
    /// predates tags has no `ArchiveTag` record type at all, because CloudKit makes a type exist
    /// on the first save of one. And a type made that way has no queryable index on `recordName`,
    /// so asking it for everything answers `invalidArguments` until the index is added in the
    /// CloudKit dashboard and deployed — the same step every record type here has already had.
    /// Letting either error out took the whole archive down: folders and files had been read
    /// successfully and the pane still said it could not be loaded.
    /// Identifiers only, and none where the archive cannot answer for them — the same two ways a
    /// tag query fails as in `fetchTagRecords`, neither of which should fail a deletion of
    /// everything else.
    private func fetchTagRecordIDs() async throws -> [CKRecord.ID] {
        do {
            return try await fetchAllRecords(
                ofType: CloudKitSchema.RecordType.tag,
                desiredKeys: []
            ).map(\.recordID)
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            return []
        }
    }

    private func fetchTagRecords() async throws -> [CKRecord] {
        do {
            return try await fetchAllRecords(ofType: CloudKitSchema.RecordType.tag)
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            return []
        }
    }

    func save(tag: ArchiveTag) async throws {
        try await requireAvailableAccount()
        let recordID = CKRecord.ID(recordName: tag.id.uuidString)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitSchema.RecordType.tag, recordID: recordID)
        }
        CloudKitRecordMapper.update(record, from: tag)
        _ = try await database.save(record)
    }

    func delete(tag: ArchiveTag) async throws {
        try await requireAvailableAccount()
        _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: tag.id.uuidString))
    }

    func fileContentURL(for fileID: UUID) async throws -> URL {
        try await requireAvailableAccount()
        let recordID = CKRecord.ID(recordName: fileID.uuidString)
        let record = try await database.record(for: recordID)
        guard let asset = record[CloudKitSchema.Field.asset] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudKitRepositoryError.missingAsset
        }
        return fileURL
    }

    func save(folder: ArchiveFolder) async throws {
        try await requireAvailableAccount()
        let recordID = CKRecord.ID(recordName: folder.id.uuidString)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitSchema.RecordType.folder, recordID: recordID)
        }
        CloudKitRecordMapper.update(record, from: folder)
        _ = try await database.save(record)
    }

    func save(file: ArchiveFile) async throws {
        try await save(file: file, assetURL: nil)
    }

    func save(file: ArchiveFile, assetURL: URL) async throws {
        try await save(file: file, assetURL: Optional(assetURL))
    }

    private func save(file: ArchiveFile, assetURL: URL?) async throws {
        try await requireAvailableAccount()
        let recordID = CKRecord.ID(recordName: file.id.uuidString)
        try await writingOneAtATime(to: recordID) {
            let record: CKRecord
            do {
                record = try await self.database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: CloudKitSchema.RecordType.file, recordID: recordID)
            }
            CloudKitRecordMapper.update(record, from: file, assetURL: assetURL)
            _ = try await self.database.save(record)
        }
        if file.importState == .completed {
            recentCompletedFilesByHash[file.contentHash.lowercased()] = file
        }
    }

    /// Many files, read together and written together.
    ///
    /// Two round trips for as many as CloudKit will take at once, rather than two for each file.
    /// The read is what a single save does too — a record is fetched, changed, and put back — but
    /// asked for the whole set at once, so the archive answers about twenty files in the time it
    /// answered about one.
    ///
    /// Not atomic. A selection is a list of separate intentions, so one file the server refuses is
    /// one file the reader is told about, not nineteen edits thrown away. What could not be written
    /// comes back with its reason.
    func save(files: [ArchiveFile]) async throws -> [UUID: any Error] {
        guard !files.isEmpty else { return [:] }
        try await requireAvailableAccount()

        var failures: [UUID: any Error] = [:]
        for start in stride(from: 0, to: files.count, by: Self.batchSize) {
            let chunk = Array(files[start..<min(start + Self.batchSize, files.count)])
            let recordIDs = chunk.map { CKRecord.ID(recordName: $0.id.uuidString) }
            // A file the archive has never heard of has no record to read; it is written as a new
            // one, exactly as the single save does.
            let existing = try await database.records(for: recordIDs)
            var records: [CKRecord] = []
            for file in chunk {
                let recordID = CKRecord.ID(recordName: file.id.uuidString)
                let record: CKRecord
                switch existing[recordID] {
                case .success(let found):
                    record = found
                case .failure(let error as CKError) where error.code == .unknownItem:
                    record = CKRecord(recordType: CloudKitSchema.RecordType.file, recordID: recordID)
                case .failure(let error):
                    failures[file.id] = error
                    continue
                case nil:
                    record = CKRecord(recordType: CloudKitSchema.RecordType.file, recordID: recordID)
                }
                CloudKitRecordMapper.update(record, from: file, assetURL: nil)
                records.append(record)
            }
            guard !records.isEmpty else { continue }

            let (saveResults, _) = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for (recordID, result) in saveResults {
                guard let id = UUID(uuidString: recordID.recordName) else { continue }
                if case .failure(let error) = result { failures[id] = error }
            }
        }

        for file in files where file.importState == .completed && failures[file.id] == nil {
            recentCompletedFilesByHash[file.contentHash.lowercased()] = file
        }
        return failures
    }

    /// Imported files, written where they are known to be new.
    ///
    /// Nothing is read. An import has just minted these identifiers, so the fetch `save(file:)`
    /// performs could only ever answer that the record does not exist — measured against the real
    /// archive that answer cost about 550 ms per file, and an import paid for it twice, because the
    /// record was written once empty and once with its payload. Here each file is one record, built
    /// rather than fetched, and as many of them as one request should carry go together.
    ///
    /// How many that is comes from what they carry rather than from counting them. A bookmark is
    /// about 270 bytes, so a fixed twenty of them was a round trip spent on five kilobytes — and a
    /// bookmark export is thousands of bookmarks, which made it the slowest import there is by a
    /// wide margin while being the smallest by bytes.
    ///
    /// Not atomic, and one refused file is one file the reader is told about. A batch that fails as
    /// a whole — the network, the account — stops the run, and what was never sent says so.
    func create(files: [ArchiveFileAsset]) async throws -> [UUID: any Error] {
        guard !files.isEmpty else { return [:] }
        try await requireAvailableAccount()

        var failures: [UUID: any Error] = [:]
        var written: [ArchiveFile] = []
        var stopped = false
        let batches = ArchiveWriteBatch.split(
            files,
            maximumCount: Self.batchSize,
            maximumBytes: Self.importByteBudget,
            bytes: \.file.fileSize
        )
        for chunk in batches {
            guard !stopped else {
                chunk.forEach { failures[$0.file.id] = ArchiveWriteNotAttempted() }
                continue
            }
            do {
                try Task.checkCancellation()
                let (saveResults, _) = try await database.modifyRecords(
                    saving: chunk.map { entry in
                        let record = CKRecord(
                            recordType: CloudKitSchema.RecordType.file,
                            recordID: CKRecord.ID(recordName: entry.file.id.uuidString)
                        )
                        CloudKitRecordMapper.update(record, from: entry.file, assetURL: entry.assetURL)
                        return record
                    },
                    deleting: [],
                    savePolicy: .allKeys,
                    atomically: false
                )
                for (recordID, result) in saveResults {
                    guard let id = UUID(uuidString: recordID.recordName) else { continue }
                    if case .failure(let error) = result { failures[id] = error }
                }
                written.append(contentsOf: chunk.map(\.file).filter { failures[$0.id] == nil })
            } catch {
                chunk.forEach { failures[$0.file.id] = error }
                stopped = true
            }
        }

        for file in written where file.importState == .completed {
            recentCompletedFilesByHash[file.contentHash.lowercased()] = file
        }
        return failures
    }

    /// What CloudKit takes in one operation. The Trash's own delete has always chunked at this
    /// number; a write is no different.
    private static let batchSize = 200

    /// Fewer, where each record brings a payload with it. The number above is about records; this
    /// one is about bytes, and two hundred files carrying assets is a single request large enough
    /// for the server to refuse outright. Twenty still turns forty round trips per twenty files
    /// into one, so nearly all of the saving is here, and what is left to gain is not worth
    /// standing on a limit whose exact value is undocumented.
    ///
    /// **Unverified against the real service at size.** Chosen to be safe rather than measured; the
    /// largest restore anyone has run here is small enough that no batch size would show.
    ///
    /// Restore alone, now. The import decides by bytes instead — see `importByteBudget` — and this
    /// number stays here rather than being changed with it, because restore has been confirmed
    /// against real data at this size and nothing about it is reported slow. The same rule would
    /// suit it, and its request can be larger than the import's ever gets, since the 500 MB batch
    /// limit an import obeys does not apply to a package being put back. That is a reason to look
    /// again, not a reason to change it while looking at something else.
    private static let assetBatchSize = 20

    /// What one imported-file write may carry between all of its records.
    ///
    /// Below what the import path could already put in a single request: twenty files at the 25 MB
    /// an image may reach is 500 MB, and the whole-import limit permits exactly that. So this makes
    /// a request smaller than it used to be and never larger, while letting small payloads fill the
    /// record count the rest of the archive already writes at. An ordinary selection of photos still
    /// goes in one request; what gets split is video, which is the one payload large enough that a
    /// single request should not carry several of them.
    private static let importByteBudget: Int64 = 100 * 1_024 * 1_024

    func createInEmptyArchive(tags: [ArchiveTag]) async throws {
        try await requireAvailableAccount()
        try await creating(tags, batchSize: Self.batchSize) { tag in
            let record = CKRecord(
                recordType: CloudKitSchema.RecordType.tag,
                recordID: CKRecord.ID(recordName: tag.id.uuidString)
            )
            CloudKitRecordMapper.update(record, from: tag)
            return record
        }
    }

    func create(folders: [ArchiveFolder]) async throws {
        try await requireAvailableAccount()
        try await creating(folders, batchSize: Self.batchSize) { folder in
            let record = CKRecord(
                recordType: CloudKitSchema.RecordType.folder,
                recordID: CKRecord.ID(recordName: folder.id.uuidString)
            )
            CloudKitRecordMapper.update(record, from: folder)
            return record
        }
    }

    func createInEmptyArchive(files: [ArchiveFileAsset]) async throws {
        try await requireAvailableAccount()
        try await creating(files, batchSize: Self.assetBatchSize) { entry in
            let record = CKRecord(
                recordType: CloudKitSchema.RecordType.file,
                recordID: CKRecord.ID(recordName: entry.file.id.uuidString)
            )
            CloudKitRecordMapper.update(record, from: entry.file, assetURL: entry.assetURL)
            return record
        }
        for entry in files where entry.file.importState == .completed {
            recentCompletedFilesByHash[entry.file.contentHash.lowercased()] = entry.file
        }
    }

    /// New records, built rather than fetched, written in batches until one is refused.
    ///
    /// `savePolicy` is `.allKeys` because there is no server record to have changed underneath
    /// these — the caller has established that the archive is empty, which is the whole reason this
    /// path exists.
    ///
    /// The count comes from what the server actually accepted rather than from the size of the
    /// batch. The private database's default zone does not honour atomic writes, so part of a batch
    /// can land, and a caller told "twenty written" when nineteen were would report a boundary that
    /// is not there.
    private func creating<Item>(
        _ items: [Item],
        batchSize: Int,
        makeRecord: (Item) -> CKRecord
    ) async throws {
        var written = 0
        for start in stride(from: 0, to: items.count, by: batchSize) {
            let chunk = Array(items[start..<min(start + batchSize, items.count)])
            do {
                try Task.checkCancellation()
                let (saveResults, _) = try await database.modifyRecords(
                    saving: chunk.map(makeRecord),
                    deleting: [],
                    savePolicy: .allKeys,
                    atomically: true
                )
                var firstFailure: (any Error)?
                for result in saveResults.values {
                    switch result {
                    case .success:
                        written += 1
                    case .failure(let error):
                        firstFailure = firstFailure ?? error
                    }
                }
                if let firstFailure {
                    throw ArchivePartialWriteFailure(writtenCount: written, underlying: firstFailure)
                }
            } catch let failure as ArchivePartialWriteFailure {
                throw failure
            } catch {
                throw ArchivePartialWriteFailure(writtenCount: written, underlying: error)
            }
        }
    }

    /// Holds a write until the one before it on the same record has finished.
    ///
    /// A write reads the record, changes it, and puts it back. Two of them in flight together read
    /// the same version, and the server refuses the one that arrives second — CloudKit's client
    /// oplock error. Being an actor is not enough on its own: each `await` here is a point where the
    /// next write can start. Tapping the star twice quickly was enough to see it, and every edit
    /// that saves a file could reach it the same way.
    ///
    /// Waiting rather than dropping: each tap is something the reader asked for, and they arrive in
    /// the order they were made.
    private func writingOneAtATime(
        to recordID: CKRecord.ID,
        _ write: @escaping @Sendable () async throws -> Void
    ) async throws {
        let previous = writesInFlight[recordID]
        let attempt = Task<(any Error)?, Never> {
            await previous?.value
            do {
                try await write()
                return nil
            } catch {
                return error
            }
        }
        writesInFlight[recordID] = Task { _ = await attempt.value }
        if let error = await attempt.value { throw error }
    }

    /// One question for a whole import, and none at all for what the session already knows.
    ///
    /// A launch reads every file record, so the hash of everything already on the shelf and in the
    /// Trash is in hand before an import starts; only hashes the session has not seen reach the
    /// service. Those go in one query per hundred rather than one per file, and without the asset:
    /// the answer needed is a name and whether it is discarded.
    func files(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile] {
        var matches: [String: ArchiveFile] = [:]
        var unknown: [String] = []
        for hash in hashes {
            let normalized = hash.lowercased()
            if let recentFile = recentCompletedFilesByHash[normalized] {
                matches[normalized] = recentFile
            } else {
                unknown.append(normalized)
            }
        }
        guard !unknown.isEmpty else { return matches }
        try await requireAvailableAccount()

        for start in stride(from: 0, to: unknown.count, by: Self.hashQueryBatchSize) {
            let chunk = Array(unknown[start..<min(start + Self.hashQueryBatchSize, unknown.count)])
            let query = CKQuery(
                recordType: CloudKitSchema.RecordType.file,
                predicate: NSPredicate(format: "%K IN %@", CloudKitSchema.Field.contentHash, chunk)
            )
            let records = try await fetchRecords(
                matching: query,
                desiredKeys: CloudKitSchema.fileMetadataFields
            )
            for file in try records.map(CloudKitRecordMapper.file(from:))
            where file.importState == .completed {
                let normalized = file.contentHash.lowercased()
                if matches[normalized] == nil { matches[normalized] = file }
            }
        }
        return matches
    }

    /// Hashes per duplicate query. The predicate is sent to the server, and a list without a bound
    /// would grow with the import until the query itself was refused.
    private static let hashQueryBatchSize = 100

    private func requireAvailableAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitRepositoryError.iCloudUnavailable
        }
    }

    private func fetchAllRecords(
        ofType recordType: String,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        return try await fetchRecords(matching: query, desiredKeys: desiredKeys)
    }

    /// `desiredKeys` is what the caller will actually read. Passing `nil` asks for every field,
    /// which on a file record means its `CKAsset` as well — the whole payload, fetched and written
    /// to disk by the framework before the query returns. A caller that only wants to know which
    /// records exist should never pay that, and an empty array asks for nothing but the identifiers.
    private func fetchRecords(
        matching query: CKQuery,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord] {
        var response = try await database.records(matching: query, desiredKeys: desiredKeys)
        var records = try response.matchResults.map { try $0.1.get() }

        while let cursor = response.queryCursor {
            response = try await database.records(
                continuingMatchFrom: cursor,
                desiredKeys: desiredKeys
            )
            records.append(contentsOf: try response.matchResults.map { try $0.1.get() })
        }
        return records
    }

    /// Where a record sits and whether it is discarded — all a delete needs to decide what it
    /// reaches. Enumerating these instead of whole records is the difference between reading the
    /// Trash and reading the archive.
    private struct RecordPlacement: ArchivePlaced {
        let id: UUID
        let recordID: CKRecord.ID
        let parentFolderID: UUID?
        let isTrashed: Bool
    }

    private static let placementKeys = [
        CloudKitSchema.Field.parentFolder,
        CloudKitSchema.Field.isTrashed
    ]

    private func fetchPlacements(ofType recordType: String) async throws -> [RecordPlacement] {
        try await fetchAllRecords(ofType: recordType, desiredKeys: Self.placementKeys)
            .compactMap { record in
                guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
                let parentReference = record[CloudKitSchema.Field.parentFolder] as? CKRecord.Reference
                return RecordPlacement(
                    id: id,
                    recordID: record.recordID,
                    parentFolderID: parentReference.flatMap { UUID(uuidString: $0.recordID.recordName) },
                    isTrashed: (record[CloudKitSchema.Field.isTrashed] as? NSNumber)?.boolValue ?? false
                )
            }
    }
}

extension CloudKitArchiveRepository: ArchiveResetting {
    func resetArchive() async throws -> ArchiveResetResult {
        try await requireAvailableAccount()

        // Identifiers only. Everything here is going, so nothing about any of it needs reading.
        let fileRecordIDs = try await fetchAllRecords(
            ofType: CloudKitSchema.RecordType.file,
            desiredKeys: []
        ).map(\.recordID)
        let folderRecordIDs = try await fetchAllRecords(
            ofType: CloudKitSchema.RecordType.folder,
            desiredKeys: []
        ).map(\.recordID)
        // Tags are part of the archive being deleted. They were left behind until now, and it did
        // not show, because reading the archive afterwards found names nothing carried and swept
        // them up. That sweep was deleting a reader's tags in other circumstances and is gone, so
        // what it was covering for is visible: an archive deleted on one device kept its tag rows
        // on another, and on this one too as soon as it read again.
        let tagRecordIDs = try await fetchTagRecordIDs()

        let deletedFileCount = try await deleteRecords(
            fileRecordIDs,
            previouslyDeletedFileCount: 0,
            previouslyDeletedFolderCount: 0,
            deletingFiles: true
        )
        let deletedFolderCount = try await deleteRecords(
            folderRecordIDs,
            previouslyDeletedFileCount: deletedFileCount,
            previouslyDeletedFolderCount: 0,
            deletingFiles: false
        )
        // Last, and not counted with the rest: a tag is an attribute of what has just gone, not an
        // item of the reader's that was holding anything.
        _ = try await deleteRecords(
            tagRecordIDs,
            previouslyDeletedFileCount: deletedFileCount,
            previouslyDeletedFolderCount: deletedFolderCount,
            deletingFiles: false
        )
        recentCompletedFilesByHash.removeAll()

        return ArchiveResetResult(
            deletedFolderCount: deletedFolderCount,
            deletedFileCount: deletedFileCount
        )
    }

    private func deleteRecords(
        _ recordIDs: [CKRecord.ID],
        previouslyDeletedFileCount: Int,
        previouslyDeletedFolderCount: Int,
        deletingFiles: Bool
    ) async throws -> Int {
        var deletedCount = 0
        for startIndex in stride(from: 0, to: recordIDs.count, by: 200) {
            let endIndex = min(startIndex + 200, recordIDs.count)
            do {
                let (_, deleteResults) = try await database.modifyRecords(
                    saving: [],
                    deleting: Array(recordIDs[startIndex..<endIndex]),
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: true
                )
                for result in deleteResults.values {
                    _ = try result.get()
                }
                deletedCount += endIndex - startIndex
            } catch {
                throw ArchiveResetPartialFailure(
                    deletedFolderCount: previouslyDeletedFolderCount + (deletingFiles ? 0 : deletedCount),
                    deletedFileCount: previouslyDeletedFileCount + (deletingFiles ? deletedCount : 0),
                    underlyingMessage: error.localizedDescription
                )
            }
        }
        return deletedCount
    }
}

extension CloudKitArchiveRepository: IncompleteImportPurging {
    func fetchIncompleteImportCount() async throws -> Int {
        try await incompleteImportRecordIDs().count
    }

    func removeIncompleteImports() async throws -> IncompleteImportPurgeResult {
        let recordIDs = try await incompleteImportRecordIDs()
        let deletedFileCount = try await deleteRecords(
            recordIDs,
            previouslyDeletedFileCount: 0,
            previouslyDeletedFolderCount: 0,
            deletingFiles: true
        )
        return IncompleteImportPurgeResult(deletedFileCount: deletedFileCount)
    }

    /// The session duplicate cache holds completed files only, so it is left in place here.
    private func incompleteImportRecordIDs() async throws -> [CKRecord.ID] {
        try await requireAvailableAccount()
        return try await fetchAllRecords(
            ofType: CloudKitSchema.RecordType.file,
            desiredKeys: [CloudKitSchema.Field.importState]
        )
        .filter { record in
            let state = ImportState(rawValue: record[CloudKitSchema.Field.importState] as? String ?? "")
            return (state ?? .completed) != .completed
        }
        .map(\.recordID)
    }
}

extension CloudKitArchiveRepository {
    func permanentlyDelete(_ item: ArchiveItem) async throws -> ArchiveDeletionResult {
        try await requireAvailableAccount()

        switch item {
        case .file(let file):
            let recordID = CKRecord.ID(recordName: file.id.uuidString)
            // One field, not the whole record: the question is whether this file is in the Trash,
            // and reading the rest means downloading the payload of a file about to be deleted.
            let found = try await database.records(
                for: [recordID],
                desiredKeys: [CloudKitSchema.Field.isTrashed]
            )
            guard let record = try found[recordID]?.get(),
                  (record[CloudKitSchema.Field.isTrashed] as? NSNumber)?.boolValue == true else {
                throw ArchiveValidationError.missingParent
            }
            let deletedCount = try await deleteRecords(
                [recordID],
                previouslyDeletedFileCount: 0,
                previouslyDeletedFolderCount: 0,
                deletingFiles: true
            )
            recentCompletedFilesByHash.removeAll()
            return ArchiveDeletionResult(deletedFolderCount: 0, deletedFileCount: deletedCount)

        case .folder(let folder):
            let folders = try await fetchPlacements(ofType: CloudKitSchema.RecordType.folder)
            guard folders.first(where: { $0.id == folder.id })?.isTrashed == true else {
                throw ArchiveValidationError.missingParent
            }
            let subtreeIDs = ArchiveTrashFilter.subtreeFolderIDs(
                rootedAt: [folder.id],
                folders: folders
            )
            let files = try await fetchPlacements(ofType: CloudKitSchema.RecordType.file)
            return try await purgeRecords(
                fileIDs: files
                    .filter { $0.parentFolderID.map(subtreeIDs.contains) ?? false }
                    .map(\.recordID),
                folderIDs: folders
                    .filter { subtreeIDs.contains($0.id) }
                    .map(\.recordID)
            )
        }
    }

    func emptyTrash() async throws -> ArchiveDeletionResult {
        try await requireAvailableAccount()
        // What is in the Trash is still worked out from the tree, because a folder in the Trash is
        // marked but the things inside it are not. That derivation needs each record's parent and
        // its own flag, and nothing else — not the names, not the payloads.
        let folders = try await fetchPlacements(ofType: CloudKitSchema.RecordType.folder)
        let folderIDs = ArchiveTrashFilter.subtreeFolderIDs(
            rootedAt: Set(folders.filter(\.isTrashed).map(\.id)),
            folders: folders
        )
        let files = try await fetchPlacements(ofType: CloudKitSchema.RecordType.file)
        return try await purgeRecords(
            fileIDs: files
                .filter { $0.isTrashed || ($0.parentFolderID.map(folderIDs.contains) ?? false) }
                .map(\.recordID),
            folderIDs: folders
                .filter { folderIDs.contains($0.id) }
                .map(\.recordID)
        )
    }

    private func purgeRecords(
        fileIDs: [CKRecord.ID],
        folderIDs: [CKRecord.ID]
    ) async throws -> ArchiveDeletionResult {
        let deletedFileCount = try await deleteRecords(
            fileIDs,
            previouslyDeletedFileCount: 0,
            previouslyDeletedFolderCount: 0,
            deletingFiles: true
        )
        let deletedFolderCount = try await deleteRecords(
            folderIDs,
            previouslyDeletedFileCount: deletedFileCount,
            previouslyDeletedFolderCount: 0,
            deletingFiles: false
        )
        recentCompletedFilesByHash.removeAll()
        return ArchiveDeletionResult(
            deletedFolderCount: deletedFolderCount,
            deletedFileCount: deletedFileCount
        )
    }
}
