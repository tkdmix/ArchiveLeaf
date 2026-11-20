import Foundation

/// Writes archived bytes out as a real file, under the name the archive knows them by.
///
/// Both sharing and Quick Look work from a URL whose extension names the type. The content cache is
/// keyed by hash and its files carry neither a name nor an extension, so it cannot be handed over.
enum PreviewFileStore {
    private static let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ArchiveLeafPreview", isDirectory: true)

    /// A directory per file, so two pictures sharing a name do not collide, and so a picture
    /// already written stays written — Quick Look asks for the neighbours again as it pages.
    static func write(_ data: Data, named fileName: String, for id: UUID) throws -> URL {
        let itemDirectory = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let url = itemDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
}
