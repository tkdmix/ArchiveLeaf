import CryptoKit
import Foundation

/// Brings another app's bookmarks onto the shelf, under that app's own name.
///
/// Not the ordinary import path, and deliberately so. That one names every refusal to the reader,
/// which is right for a handful of files a person just dropped and wrong here: an export is mostly
/// things the shelf may already hold, and a list of thousands of them says nothing. This counts what
/// it skipped instead, and keeps going.
///
/// Nothing is fetched. A bookmark is the same standard `.webloc` property list every other way in
/// produces, so an imported bookmark and one entered by hand are the same kind of thing afterwards.
struct BookmarkImportService: BookmarkImporting {
    private let repository: any ArchiveRepository
    private let policy: ImportPolicy
    /// The export file itself, which is read whole. A bookmark is a few hundred bytes, so this is
    /// a limit on a plainly broken input rather than on how many bookmarks a person may keep.
    private let maximumExportSize: Int64

    init(
        repository: any ArchiveRepository,
        policy: ImportPolicy = ImportPolicy(),
        maximumExportSize: Int64 = 20 * 1_024 * 1_024
    ) {
        self.repository = repository
        self.policy = policy
        self.maximumExportSize = maximumExportSize
    }

    func importBookmarks(
        from fileURL: URL,
        source: BookmarkImportSource
    ) async throws -> BookmarkImportSummary {
        let isAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { fileURL.stopAccessingSecurityScopedResource() }
        }

        let parsed = try source.parseBookmarks(from: try exportData(at: fileURL))

        let snapshot = try await repository.fetchSnapshot()
        let trashedFiles = (try? await repository.fetchTrashedFiles()) ?? []
        var state = ImportWorkingSet(
            folders: snapshot.folders,
            files: snapshot.files,
            tags: snapshot.tags,
            trashedFiles: trashedFiles
        )

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeaf-BookmarkImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        var duplicateCount = 0
        var failures: [String] = []
        let unreadableCount = parsed.unreadableCount
        // Staged rather than written one at a time. An export is thousands of bookmarks, and a
        // bookmark written on its own was two round trips to place a record and two more to fill it
        // in — about two seconds each against the real archive, for a few hundred bytes.
        var staged: [ArchiveFileAsset] = []
        var sourceURLsByFileID: [UUID: URL] = [:]

        let rootFolderID = try await folderID(
            forPath: [source.name],
            state: &state
        )

        for bookmark in parsed.bookmarks {
            do {
                try Task.checkCancellation()
                let data = try BookmarkDocument.data(for: bookmark.url)
                let contentHash = Self.sha256(of: data)
                guard state.insertHashIfNew(contentHash) else {
                    duplicateCount += 1
                    continue
                }
                let components = Array(bookmark.folderPathComponents.prefix(policy.maximumFolderDepth - 1))
                let parentID = try await folderID(
                    forPath: [source.name] + components,
                    startingAt: rootFolderID,
                    state: &state
                )
                let tagIDs = try await tagIDs(for: bookmark, source: source, state: &state)
                let entry = try stage(
                    bookmark,
                    data: data,
                    contentHash: contentHash,
                    in: parentID,
                    tagIDs: tagIDs,
                    stagingDirectory: stagingDirectory,
                    state: &state
                )
                staged.append(entry)
                sourceURLsByFileID[entry.file.id] = bookmark.url
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(bookmark.url.absoluteString): \(error.localizedDescription)")
            }
        }

        // One write for the whole export, in batches. Anything the archive refuses is named and the
        // rest still lands, which is this importer's rule everywhere else too.
        let writeFailures = try await repository.create(files: staged)
        for (fileID, error) in writeFailures {
            let address = sourceURLsByFileID[fileID]?.absoluteString ?? ""
            failures.append("\(address): \(error.localizedDescription)")
        }
        state.files.removeAll { writeFailures[$0.id] != nil }
        let importedCount = staged.count - writeFailures.count

        return BookmarkImportSummary(
            source: source,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            unreadableCount: unreadableCount,
            failures: failures,
            snapshot: ArchiveSnapshot(
                folders: state.folders,
                files: state.files,
                tags: state.tags
            )
        )
    }

    private func exportData(at fileURL: URL) throws -> Data {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, Int64(size) > maximumExportSize {
            throw BookmarkImportError.fileSizeExceeded(maximumExportSize)
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            throw BookmarkImportError.unreadableFile
        }
        guard !data.isEmpty else { throw BookmarkImportError.emptyFile }
        return data
    }

    /// The archive as this import has made it so far.
    ///
    /// Held rather than re-read: every bookmark needs to know the names already used beside it and
    /// the folders already made for it, and asking CloudKit each time would be a round trip per
    /// bookmark to learn what this loop already knows.
    private struct ImportWorkingSet {
        var folders: [ArchiveFolder]
        var files: [ArchiveFile]
        var tags: [ArchiveTag]
        private var contentHashes: Set<String>

        init(
            folders: [ArchiveFolder],
            files: [ArchiveFile],
            tags: [ArchiveTag],
            trashedFiles: [ArchiveFile]
        ) {
            self.folders = folders
            self.files = files
            self.tags = tags
            // The Trash counts. Identical content already on the shelf is identical content
            // whether or not the reader has put it away, and the ordinary import says so too.
            contentHashes = Set(
                (files + trashedFiles).map(\.contentHash).filter { !$0.isEmpty }
            )
        }

        /// Whether this content is new, recording it when it is. Two exports of the same page, and
        /// the same page twice within one export, are both answered here.
        mutating func insertHashIfNew(_ hash: String) -> Bool {
            contentHashes.insert(hash).inserted
        }

        func folder(named name: String, in parentID: UUID?) -> ArchiveFolder? {
            let normalized = ArchiveRules.normalizedName(name)
            return folders.first {
                !$0.isTrashed && $0.parentFolderID == parentID
                    && ArchiveRules.normalizedName($0.name) == normalized
            }
        }

        func tag(named name: String) -> ArchiveTag? {
            tags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }

        /// A name no sibling is using, which is what the archive requires of every row.
        func availableName(_ base: String, in parentID: UUID?) -> String {
            let taken = Set(
                folders.filter { !$0.isTrashed && $0.parentFolderID == parentID }
                    .map { ArchiveRules.normalizedName($0.name) }
                    + files.filter { !$0.isTrashed && $0.parentFolderID == parentID }
                    .map { ArchiveRules.normalizedName($0.displayName) }
            )
            guard taken.contains(ArchiveRules.normalizedName(base)) else { return base }
            var suffix = 2
            while taken.contains(ArchiveRules.normalizedName("\(base) \(suffix)")) {
                suffix += 1
            }
            return "\(base) \(suffix)"
        }
    }

    /// The folder at a path, made where it is not already there.
    ///
    /// Reuse is the point. A second import must land in the folder the first one made, so an
    /// existing `Raindrop` is used rather than a `Raindrop 2` appearing beside it.
    private func folderID(
        forPath components: [String],
        startingAt knownID: UUID? = nil,
        state: inout ImportWorkingSet
    ) async throws -> UUID? {
        var parentID: UUID?
        for (index, name) in components.enumerated() {
            if index == 0, let knownID {
                parentID = knownID
                continue
            }
            if let existing = state.folder(named: name, in: parentID) {
                parentID = existing.id
                continue
            }
            let folder = ArchiveFolder(
                name: state.availableName(name, in: parentID),
                parentFolderID: parentID
            )
            try await repository.save(folder: folder)
            state.folders.append(folder)
            parentID = folder.id
        }
        return parentID
    }

    private func tagIDs(
        for bookmark: ImportedBookmark,
        source: BookmarkImportSource,
        state: inout ImportWorkingSet
    ) async throws -> [UUID] {
        var ids: [UUID] = []
        for sourceTagName in bookmark.tagNames {
            guard let name = source.tagName(for: sourceTagName) else { continue }
            if let existing = state.tag(named: name) {
                if !ids.contains(existing.id) { ids.append(existing.id) }
                continue
            }
            let tag = ArchiveTag(name: name)
            try await repository.save(tag: tag)
            state.tags.append(tag)
            ids.append(tag.id)
        }
        return ids
    }

    /// Writes the bookmark's payload where the batch can find it, and takes the name it will use.
    ///
    /// The file joins the working set here rather than after the write, because the next bookmark's
    /// name depends on it. What the archive refuses is taken out again before the summary is built.
    private func stage(
        _ bookmark: ImportedBookmark,
        data: Data,
        contentHash: String,
        in parentID: UUID?,
        tagIDs: [UUID],
        stagingDirectory: URL,
        state: inout ImportWorkingSet
    ) throws -> ArchiveFileAsset {
        let title = bookmark.title.isEmpty
            ? (bookmark.url.host ?? String(localized: "Bookmark"))
            : bookmark.title
        let name = state.availableName(BookmarkDocument.safeFileName(for: title), in: parentID)

        // One directory per bookmark: two bookmarks with the same name in different folders would
        // otherwise overwrite each other on the way in.
        let itemDirectory = stagingDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let assetURL = itemDirectory.appendingPathComponent("\(name).webloc", isDirectory: false)
        try data.write(to: assetURL, options: .atomic)

        let file = ArchiveFile(
            originalFileName: assetURL.lastPathComponent,
            parentFolderID: parentID,
            tagIDs: tagIDs,
            isFavorite: bookmark.isFavorite,
            detectedFormat: .bookmark,
            sourceModifiedAt: bookmark.addedAt,
            fileSize: Int64(data.count),
            contentHash: contentHash,
            importState: .completed
        )
        state.files.append(file)
        return ArchiveFileAsset(file: file, assetURL: assetURL)
    }

    /// The same digest the ordinary import stores, so a bookmark imported here and the identical
    /// `.webloc` dropped in are recognised as one thing in either order.
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
