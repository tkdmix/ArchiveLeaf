import Foundation

struct ArchiveSnapshot: Codable, Sendable {
    let folders: [ArchiveFolder]
    let files: [ArchiveFile]
    let tags: [ArchiveTag]

    init(folders: [ArchiveFolder], files: [ArchiveFile], tags: [ArchiveTag] = []) {
        self.folders = folders
        self.files = files
        self.tags = tags
    }
}
