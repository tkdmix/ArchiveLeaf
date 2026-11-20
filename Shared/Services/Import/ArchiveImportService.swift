import Foundation

/// Writes accepted files into the archive as one piece of work.
///
/// One record per file, written straight to `completed` with its payload. There is no longer an
/// empty record placed first: nothing read it, a write either lands or does not, and the record it
/// left behind when an import was interrupted was the reason the archive could hold files no screen
/// showed. What that placeholder cost was two round trips a file — and a third, because the record
/// had to be read back before it could be completed.
struct ArchiveImportService: ArchiveImporting {
    private let repository: any ArchiveRepository

    init(repository: any ArchiveRepository) {
        self.repository = repository
    }

    func importFiles(_ placements: [ImportPlacement]) async -> ArchiveImportOutcome {
        guard !placements.isEmpty else {
            return ArchiveImportOutcome(importedFiles: [], failures: [])
        }

        var entries: [ArchiveFileAsset] = []
        var candidatesByFileID: [UUID: ImportCandidate] = [:]
        var failures: [ImportFailure] = []

        for placement in placements {
            guard case .viewable(let format, let encoding) = placement.candidate.detection else {
                failures.append(ImportFailure(
                    sourceURL: placement.candidate.sourceURL,
                    reason: ArchiveImportError.notViewable.localizedDescription
                ))
                continue
            }
            let file = ArchiveFile(
                originalFileName: placement.candidate.sourceURL.lastPathComponent,
                parentFolderID: placement.folderID,
                detectedFormat: format,
                sourceEncoding: encoding,
                sourceModifiedAt: placement.candidate.sourceModifiedAt,
                fileSize: placement.candidate.fileSize,
                contentHash: placement.candidate.contentHash,
                importState: .completed
            )
            candidatesByFileID[file.id] = placement.candidate
            entries.append(ArchiveFileAsset(file: file, assetURL: placement.candidate.sourceURL))
        }

        guard !entries.isEmpty else {
            return ArchiveImportOutcome(importedFiles: [], failures: failures)
        }

        // Held for the whole write rather than per file: the batch reads the payloads while it
        // builds one request, so access has to outlast the individual file.
        let accessed = entries.filter { $0.assetURL.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.assetURL.stopAccessingSecurityScopedResource() } }

        let writeFailures: [UUID: any Error]
        do {
            writeFailures = try await repository.create(files: entries)
        } catch {
            return ArchiveImportOutcome(
                importedFiles: [],
                failures: failures + entries.map {
                    ImportFailure(sourceURL: $0.assetURL, reason: error.localizedDescription)
                }
            )
        }

        var importedFiles: [ArchiveFile] = []
        for entry in entries {
            if let error = writeFailures[entry.file.id] {
                failures.append(ImportFailure(
                    sourceURL: candidatesByFileID[entry.file.id]?.sourceURL ?? entry.assetURL,
                    reason: error.localizedDescription
                ))
            } else {
                importedFiles.append(entry.file)
            }
        }
        return ArchiveImportOutcome(importedFiles: importedFiles, failures: failures)
    }
}

enum ArchiveImportError: LocalizedError {
    /// Reached only if preflight accepted something the importer cannot store, so it names the
    /// inconsistency rather than guessing at a cause.
    case notViewable

    var errorDescription: String? {
        String(localized: "This input cannot be stored as an archive item.")
    }
}
