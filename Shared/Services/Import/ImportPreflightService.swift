import Foundation

struct ImportPreflightService: ImportPreflightChecking {
    private let detector: any FileFormatDetecting
    private let duplicateDetector: (any DuplicateDetecting)?
    private let policy: ImportPolicy

    init(
        detector: any FileFormatDetecting = ContentFileFormatDetector(),
        duplicateDetector: (any DuplicateDetecting)? = nil,
        policy: ImportPolicy = ImportPolicy()
    ) {
        self.detector = detector
        self.duplicateDetector = duplicateDetector
        self.policy = policy
    }

    /// Looked at in three passes rather than one.
    ///
    /// What each file is, and whether the archive will take it, is decided first for everything
    /// selected. Then the archive is asked once about every hash at once, instead of once per file.
    /// Only then are the batch limits applied, in the order the selection was given.
    ///
    /// The reason for the middle pass is cost: the question "is this already archived?" is a round
    /// trip, and asking it per file is what made an import of two dozen files take a minute before
    /// the first record was written.
    func inspect(urls: [URL]) async -> ImportPreflightResult {
        var groups: [CandidateGroup] = []
        var failures: [ImportFailure] = []
        var folderPathComponents: [[String]] = []
        let temporaryDirectories: [URL] = []

        for url in urls {
            do {
                // The app's own backup is a directory, so walking into it would take it apart and
                // file the pieces — a manifest and a folder of nameless assets — as though they
                // were things worth keeping. It is restored from Settings, not imported.
                if url.pathExtension.lowercased() == ArchiveBackupPackage.pathExtension {
                    failures.append(ImportFailure(
                        sourceURL: url,
                        reason: String(localized: "This is an ArchiveLeaf backup. Restore it from Settings rather than importing it.")
                    ))
                    continue
                }
                if try isDirectory(url) {
                    let directoryResult = try await inspectDirectory(url)
                    groups.append(CandidateGroup(sourceURL: url, candidates: directoryResult.candidates))
                    folderPathComponents.append(contentsOf: directoryResult.folderPaths)
                    continue
                }
                let source = try sourceValues(for: url)
                try refuseIfLargerThanAnyLimit(source.fileSize)
                let detection = try await detector.detectFormat(for: url)

                switch detection {
                case .viewable:
                    let candidate = try await makeCandidate(
                        for: url,
                        detection: detection,
                        values: source,
                        relativePathComponents: nil
                    )
                    groups.append(CandidateGroup(sourceURL: url, candidates: [candidate]))
                case .zipArchive:
                    throw ImportPreflightError.archiveInput
                }
            } catch {
                failures.append(failure(url, error.localizedDescription))
            }
        }

        await removeAlreadyArchived(from: &groups, failures: &failures)

        var candidates: [ImportCandidate] = []
        var acceptedSize: Int64 = 0
        var acceptedHashes = Set<String>()
        var acceptedPaths = Set<String>()
        for group in groups {
            do {
                try accept(
                    group.candidates,
                    candidates: &candidates,
                    acceptedSize: &acceptedSize,
                    acceptedHashes: &acceptedHashes,
                    acceptedPaths: &acceptedPaths,
                    failures: &failures
                )
            } catch {
                failures.append(failure(group.sourceURL, error.localizedDescription))
            }
        }

        return ImportPreflightResult(
            candidates: candidates,
            failures: failures,
            folderPathComponents: uniqueFolderPaths(folderPathComponents),
            temporaryDirectoryURLs: temporaryDirectories
        )
    }

    /// Drops what the archive already holds, one file at a time.
    ///
    /// A file already on the shelf is not a reason to refuse the rest of a folder. It used to be:
    /// one photo that had been imported before failed the whole drop, and the destination folder was
    /// not even created. What the reader gets now is the same sentence about that one file, and
    /// everything else on the shelf.
    ///
    /// A lookup that cannot answer stops the import instead of guessing. The archive is the only
    /// thing that knows, and importing without asking is how the second copy gets in.
    private func removeAlreadyArchived(
        from groups: inout [CandidateGroup],
        failures: inout [ImportFailure]
    ) async {
        guard let duplicateDetector else { return }
        let hashes = Set(groups.flatMap { $0.candidates.map(\.contentHash) }.filter { !$0.isEmpty })
        guard !hashes.isEmpty else { return }

        let existing: [String: ArchiveFile]
        do {
            existing = try await duplicateDetector.existingFiles(matchingContentHashes: hashes)
        } catch {
            for candidate in groups.flatMap(\.candidates) {
                failures.append(failure(candidate.sourceURL, error.localizedDescription))
            }
            groups = []
            return
        }
        guard !existing.isEmpty else { return }

        for index in groups.indices {
            groups[index].candidates.removeAll { candidate in
                guard let match = existing[candidate.contentHash.lowercased()] else { return false }
                failures.append(failure(
                    candidate.sourceURL,
                    ImportPreflightError.duplicateExisting(
                        name: match.sidebarDisplayName,
                        isTrashed: match.isTrashed
                    ).localizedDescription
                ))
                return true
            }
        }
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private func inspectDirectory(_ directoryURL: URL) async throws -> DirectoryInspectionResult {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ImportPreflightError.unreadable
        }

        let rootName = directoryURL.lastPathComponent
        var candidates: [ImportCandidate] = []
        var folderPaths = [[rootName]]
        while let itemURL = enumerator.nextObject() as? URL {
            let values = try itemURL.resourceValues(forKeys: keys)
            let relative = [rootName] + relativeComponents(of: itemURL, in: directoryURL)
            guard relative.joined(separator: "/").count <= policy.maximumRelativePathLength else {
                throw ImportPreflightError.pathLengthExceeded(policy.maximumRelativePathLength)
            }
            if values.isSymbolicLink == true {
                throw ImportPreflightError.symbolicLink(itemURL.lastPathComponent)
            }
            if values.isDirectory == true {
                guard relative.count <= policy.maximumFolderDepth else {
                    throw ImportPreflightError.folderDepthExceeded(policy.maximumFolderDepth)
                }
                folderPaths.append(relative)
                continue
            }
            guard values.isRegularFile == true else {
                throw ImportPreflightError.notARegularFile
            }
            guard relative.count - 1 <= policy.maximumFolderDepth else {
                throw ImportPreflightError.folderDepthExceeded(policy.maximumFolderDepth)
            }
            guard let fileSize = values.fileSize else { throw ImportPreflightError.unreadable }
            try refuseIfLargerThanAnyLimit(Int64(fileSize))
            let detection = try await detector.detectFormat(for: itemURL)
            guard case .viewable = detection else {
                throw ImportPreflightError.nestedArchive(itemURL.lastPathComponent)
            }
            candidates.append(try await makeCandidate(
                for: itemURL,
                detection: detection,
                values: SourceValues(
                    fileSize: Int64(fileSize),
                    modificationDate: values.contentModificationDate
                ),
                relativePathComponents: relative
            ))
        }
        if enumerationError != nil { throw ImportPreflightError.unreadable }
        return DirectoryInspectionResult(candidates: candidates, folderPaths: uniqueFolderPaths(folderPaths))
    }

    private func uniqueFolderPaths(_ paths: [[String]]) -> [[String]] {
        var seen = Set<String>()
        return paths.sorted { $0.count < $1.count }.filter {
            seen.insert($0.map(ArchiveRules.normalizedName).joined(separator: "/")).inserted
        }
    }

    /// Before the file is opened. Detection reads it — a text file is decoded whole, once per
    /// candidate encoding — and no limit in the policy would have let a file this size in.
    private func refuseIfLargerThanAnyLimit(_ fileSize: Int64) throws {
        guard fileSize > policy.maximumAcceptableFileSize else { return }
        throw ImportPreflightError.fileSizeExceeded(policy.maximumAcceptableFileSize)
    }

    private func sourceValues(for url: URL) throws -> SourceValues {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        )
        guard values.isRegularFile == true else {
            throw ImportPreflightError.notARegularFile
        }
        guard FileManager.default.isReadableFile(atPath: url.path), let rawSize = values.fileSize else {
            throw ImportPreflightError.unreadable
        }
        return SourceValues(
            fileSize: Int64(rawSize),
            modificationDate: values.contentModificationDate
        )
    }

    private func makeCandidate(
        for url: URL,
        detection: FileDetectionResult,
        values: SourceValues,
        relativePathComponents: [String]?
    ) async throws -> ImportCandidate {
        let maximumSize = maximumSize(for: detection)
        guard values.fileSize <= maximumSize else {
            throw ImportPreflightError.fileSizeExceeded(maximumSize)
        }
        // Hashed here, matched later: the hash is local work, and the question it answers is one
        // the archive should be asked once for the whole import.
        let contentHash = try await duplicateDetector?.contentHash(for: url) ?? ""
        return ImportCandidate(
            sourceURL: url,
            detection: detection,
            fileSize: values.fileSize,
            sourceModifiedAt: values.modificationDate,
            contentHash: contentHash,
            relativePathComponents: relativePathComponents
        )
    }

    /// The limits, and what the selection says about itself.
    ///
    /// Two files with identical content are one file: the second is left out and named, the way an
    /// already-archived one is, rather than failing what it was selected alongside. The limits are
    /// the other way round — a selection over the batch size is one refusal about the selection, not
    /// a list of refusals about its files — so those still stop the group.
    private func accept(
        _ newCandidates: [ImportCandidate],
        candidates: inout [ImportCandidate],
        acceptedSize: inout Int64,
        acceptedHashes: inout Set<String>,
        acceptedPaths: inout Set<String>,
        failures: inout [ImportFailure]
    ) throws {
        var stagedSize = acceptedSize
        var stagedHashes = acceptedHashes
        var stagedPaths = acceptedPaths
        var stagedCandidates: [ImportCandidate] = []
        var stagedFailures: [ImportFailure] = []

        guard candidates.count + newCandidates.count <= policy.maximumBatchFileCount else {
            throw ImportPreflightError.batchFileCountExceeded(policy.maximumBatchFileCount)
        }
        for candidate in newCandidates {
            if !candidate.contentHash.isEmpty,
               !stagedHashes.insert(candidate.contentHash.lowercased()).inserted {
                stagedFailures.append(failure(
                    candidate.sourceURL,
                    ImportPreflightError.duplicateInSelection.localizedDescription
                ))
                continue
            }
            let (newSize, overflow) = stagedSize.addingReportingOverflow(candidate.fileSize)
            guard !overflow, newSize <= policy.maximumBatchSize else {
                throw ImportPreflightError.batchSizeExceeded(policy.maximumBatchSize)
            }
            stagedSize = newSize

            let normalizedPath = normalizedImportPath(candidate.importPathComponents)
            guard stagedPaths.insert(normalizedPath).inserted else {
                throw ImportPreflightError.duplicateName(candidate.importPathComponents.last ?? "")
            }
            stagedCandidates.append(candidate)
        }

        candidates.append(contentsOf: stagedCandidates)
        failures.append(contentsOf: stagedFailures)
        acceptedSize = stagedSize
        acceptedHashes = stagedHashes
        acceptedPaths = stagedPaths
    }

    private func normalizedImportPath(_ components: [String]) -> String {
        components.enumerated().map { index, component in
            let isFileName = index == components.count - 1
            let name = isFileName ? (component as NSString).deletingPathExtension : component
            return ArchiveRules.normalizedName(name)
        }.joined(separator: "/")
    }

    private func relativeComponents(of fileURL: URL, in directoryURL: URL) -> [String] {
        let prefix = directoryURL.standardizedFileURL.path + "/"
        let path = fileURL.standardizedFileURL.path
        return String(path.dropFirst(prefix.count)).split(separator: "/").map(String.init)
    }

    private func maximumSize(for detection: FileDetectionResult) -> Int64 {
        switch detection {
        case .zipArchive:
            // Rejected before the limit matters; kept exhaustive rather than defaulted.
            0
        case .viewable(let format, _):
            switch format {
            case .jpeg, .png: policy.maximumImageSize
            case .mp4, .mov: policy.maximumVideoSize
            case .pdf: policy.maximumPDFSize
            case .plainText, .markdown, .json, .csv, .bookmark: policy.maximumTextImportSize
            }
        }
    }

    private func failure(_ url: URL, _ reason: String) -> ImportFailure {
        ImportFailure(sourceURL: url, reason: reason)
    }
}

private struct SourceValues {
    let fileSize: Int64
    let modificationDate: Date?
}

private enum ImportPreflightError: LocalizedError {
    case notARegularFile
    case unreadable
    case fileSizeExceeded(Int64)
    case batchFileCountExceeded(Int)
    case batchSizeExceeded(Int64)
    case archiveInput
    case nestedArchive(String)
    case duplicateName(String)
    case duplicateInSelection
    case duplicateExisting(name: String, isTrashed: Bool)
    case folderDepthExceeded(Int)
    case pathLengthExceeded(Int)
    case symbolicLink(String)

    var errorDescription: String? {
        switch self {
        case .notARegularFile:
            "Folder import traversal is not available yet."
        case .unreadable:
            "The selected file is not readable."
        case .fileSizeExceeded(let limit):
            "The file exceeds the \(limit.formatted(.byteCount(style: .file))) import limit."
        case .batchFileCountExceeded(let limit):
            "The import contains more than \(limit) files."
        case .batchSizeExceeded(let limit):
            "The imported files would exceed the \(limit.formatted(.byteCount(style: .file))) batch limit."
        case .archiveInput:
            String(localized: "ArchiveLeaf does not open archives. Expand it first, then import the resulting folder.")
        case .nestedArchive(let name):
            String(localized: "“\(name)” is an archive. Expand it first, then import the resulting folder.")
        case .duplicateName(let name):
            "Multiple imported files would use the name \(name)."
        case .duplicateInSelection:
            "Another imported file has identical content."
        case .duplicateExisting(let name, let isTrashed):
            if isTrashed {
                "Identical content already exists in Trash as \(name). Restore that file instead."
            } else {
                "Identical content is already archived as \(name)."
            }
        case .folderDepthExceeded(let limit):
            "The imported folder exceeds the \(limit)-folder depth limit."
        case .pathLengthExceeded(let limit):
            "The imported path exceeds the \(limit)-character limit."
        case .symbolicLink(let name):
            "Symbolic links are not supported: \(name)"
        }
    }
}

/// One selected thing and everything acceptable found inside it. Kept together so a refusal that is
/// about the selection can still be reported against what the reader actually chose.
private struct CandidateGroup {
    let sourceURL: URL
    var candidates: [ImportCandidate]
}

private struct DirectoryInspectionResult {
    let candidates: [ImportCandidate]
    let folderPaths: [[String]]
}
