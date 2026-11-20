import Foundation

protocol ArchiveSnapshotCaching: Sendable {
    func loadSnapshot() async throws -> ArchiveSnapshot?
    func storeSnapshot(_ snapshot: ArchiveSnapshot) async throws
    func removeSnapshot() async throws
}
