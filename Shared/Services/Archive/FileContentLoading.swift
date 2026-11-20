import Foundation

protocol FileContentLoading: Sendable {
    func loadContent(for file: ArchiveFile) async throws -> LoadedFileContent

    /// The bytes as they were imported, for handing the file to somewhere else. Sharing a document
    /// means sharing the file, not a re-encoding of what was decoded to display it.
    func originalData(for file: ArchiveFile) async throws -> Data
}
