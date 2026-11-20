import Foundation

struct IncompleteImportPurgeResult: Equatable, Sendable {
    let deletedFileCount: Int
}

/// Boundary for file records that never reached `ImportState.completed`.
///
/// Interrupted or failed imports can leave such records behind. They are excluded from the
/// archive, Trash, Favorites, and duplicate matching, so this is the only place a user can see
/// that they exist and remove them. Completed files and every folder record stay untouched.
protocol IncompleteImportPurging: Sendable {
    func fetchIncompleteImportCount() async throws -> Int
    func removeIncompleteImports() async throws -> IncompleteImportPurgeResult
}
