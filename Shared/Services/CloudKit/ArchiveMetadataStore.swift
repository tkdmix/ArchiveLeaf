import Foundation

/// Boundary for metadata persistence. A CloudKit private-database implementation can be added later.
protocol ArchiveMetadataStore: Sendable {
    func fetchFolders() async throws -> [ArchiveFolder]
    func fetchFiles() async throws -> [ArchiveFile]
}
