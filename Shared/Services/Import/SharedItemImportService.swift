import Foundation

/// Imports files straight into the archive, without a review step.
///
/// Used where the user has already decided — the Share Extension — so the only questions left are
/// whether each file is acceptable. Everything lands at the archive root, which the UI already
/// presents as "Unsorted Files"; creating another similarly named folder would duplicate it.
struct SharedItemImportService: Sendable {
    struct Progress: Sendable {
        let completed: Int
        let total: Int
    }

    /// Reports the boundary rather than a single outcome: a share sheet can be torn down mid-run,
    /// and the user needs to know how much of it landed.
    struct Result: Sendable {
        let importedCount: Int
        let failures: [ImportFailure]
        let wasCancelled: Bool
    }

    private let preflight: any ImportPreflightChecking
    private let importer: any ArchiveImporting

    init(
        repository: any ArchiveRepository,
        preflight: (any ImportPreflightChecking)? = nil,
        importer: (any ArchiveImporting)? = nil
    ) {
        // Duplicate detection needs a lookup; without one the preflight simply does not perform it
        // rather than pretending a repository can answer.
        let duplicateDetector = (repository as? any DuplicateFileLookingUp)
            .map { SHA256DuplicateDetector(lookup: $0) }
        self.preflight = preflight ?? ImportPreflightService(duplicateDetector: duplicateDetector)
        self.importer = importer ?? ArchiveImportService(repository: repository)
    }

    func importFiles(
        at urls: [URL],
        onProgress: @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Result {
        let preflightResult = await preflight.inspect(urls: urls)
        let candidates = preflightResult.candidates
        let totalCount = candidates.count + preflightResult.failures.count
        guard !candidates.isEmpty else {
            return Result(importedCount: 0, failures: preflightResult.failures, wasCancelled: false)
        }

        var failures = preflightResult.failures
        if Task.isCancelled {
            return Result(importedCount: 0, failures: failures, wasCancelled: true)
        }

        // One write for everything shared. The progress bar therefore moves once rather than per
        // file, which is what a share sheet of a few items looked like anyway — and the run it
        // replaced spent about four round trips on each of those items.
        let outcome = await importer.importFiles(
            candidates.map { ImportPlacement(candidate: $0, folderID: nil) }
        )
        failures.append(contentsOf: outcome.failures)
        let importedCount = outcome.importedFiles.count
        await onProgress(Progress(completed: importedCount + failures.count, total: totalCount))

        return Result(
            importedCount: importedCount,
            failures: failures,
            wasCancelled: Task.isCancelled && importedCount < candidates.count
        )
    }

}
