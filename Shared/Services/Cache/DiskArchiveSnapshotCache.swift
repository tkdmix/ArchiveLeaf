import Foundation

actor DiskArchiveSnapshotCache: ArchiveSnapshotCaching {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func loadSnapshot() throws -> ArchiveSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try decoder.decode(ArchiveSnapshot.self, from: Data(contentsOf: fileURL))
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    func storeSnapshot(_ snapshot: ArchiveSnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func removeSnapshot() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
