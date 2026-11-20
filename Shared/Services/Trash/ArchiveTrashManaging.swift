import Foundation

struct ArchiveDeletionResult: Equatable, Sendable {
    let deletedFolderCount: Int
    let deletedFileCount: Int

    var deletedItemCount: Int { deletedFolderCount + deletedFileCount }
}

protocol ArchiveTrashPurging: Sendable {
    func permanentlyDelete(_ item: ArchiveItem) async throws -> ArchiveDeletionResult
    func emptyTrash() async throws -> ArchiveDeletionResult
}

extension ArchiveTrashPurging {
    func permanentlyDelete(_ item: ArchiveItem) async throws -> ArchiveDeletionResult {
        throw ArchiveLeafError.notImplemented
    }

    func emptyTrash() async throws -> ArchiveDeletionResult {
        throw ArchiveLeafError.notImplemented
    }
}
