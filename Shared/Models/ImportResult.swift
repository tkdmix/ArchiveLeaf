import Foundation

struct ImportResult: Sendable {
    let importedFiles: [ArchiveFile]
    let createdFolders: [ArchiveFolder]
    let failures: [ImportFailure]
}

struct ImportFailure: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let reason: String

    init(id: UUID = UUID(), sourceURL: URL, reason: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.reason = reason
    }
}
