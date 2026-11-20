import Foundation

/// Where one accepted file is going.
struct ImportPlacement: Sendable {
    let candidate: ImportCandidate
    let folderID: UUID?

    init(candidate: ImportCandidate, folderID: UUID?) {
        self.candidate = candidate
        self.folderID = folderID
    }
}

/// What landed, and what did not with the reason.
struct ArchiveImportOutcome: Sendable {
    let importedFiles: [ArchiveFile]
    let failures: [ImportFailure]
}

/// Coordinates copying immutable source content into app-managed storage.
///
/// Asked about a whole import rather than one file at a time. A file used to be two writes of its
/// own — an empty record, then the same record with its payload — and each write a read first, which
/// against the real archive was about four round trips a file before its bytes were even sent.
protocol ArchiveImporting: Sendable {
    func importFiles(_ placements: [ImportPlacement]) async -> ArchiveImportOutcome
}
