import Foundation

struct ArchiveResetResult: Equatable, Sendable {
    let deletedFolderCount: Int
    let deletedFileCount: Int

    var deletedItemCount: Int {
        deletedFolderCount + deletedFileCount
    }
}

protocol ArchiveResetting: Sendable {
    func resetArchive() async throws -> ArchiveResetResult
}

struct ArchiveResetPartialFailure: LocalizedError, Sendable {
    let deletedFolderCount: Int
    let deletedFileCount: Int
    let underlyingMessage: String

    var errorDescription: String? {
        "Deletion stopped after deleting \(deletedFileCount) files and \(deletedFolderCount) folders. \(underlyingMessage)"
    }
}

/// Posted when the archive was replaced as a whole — deleted outright, or written over by a
/// restore. The `object` is the `ArchiveSnapshot` that now exists.
///
/// The snapshot travels with the notification instead of being re-read, because CloudKit answers
/// queries from an index that lags its own writes: asking again immediately after a restore
/// returned the archive without the file that had just been written.
extension Notification.Name {
    static let archiveLeafArchiveDidReplace = Notification.Name("ArchiveLeaf.archiveDidReplace")
}
