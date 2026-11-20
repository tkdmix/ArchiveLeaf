import Foundation

struct ArchiveBackupManifest: Codable, Equatable, Sendable {
    static let formatIdentifier = "io.github.inadaman.ArchiveLeaf.backup"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let createdAt: Date
    let folders: [ArchiveFolder]
    let files: [ArchiveBackupFileEntry]
    /// The tags themselves. Files carry only ids, so without this a restored archive would hold
    /// tag ids naming nothing.
    let tags: [ArchiveTag]

    init(
        format: String = Self.formatIdentifier,
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAt: Date = .now,
        folders: [ArchiveFolder],
        files: [ArchiveBackupFileEntry],
        tags: [ArchiveTag] = []
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.folders = folders
        self.files = files
        self.tags = tags
    }

    /// Read by hand for the same reason `ArchiveFile` is: a backup made before tags has no `tags`
    /// key, and it is still a backup of a whole archive.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        folders = try container.decode([ArchiveFolder].self, forKey: .folders)
        files = try container.decode([ArchiveBackupFileEntry].self, forKey: .files)
        tags = try container.decodeIfPresent([ArchiveTag].self, forKey: .tags) ?? []
    }
}

struct ArchiveBackupFileEntry: Codable, Equatable, Sendable {
    let file: ArchiveFile
    let assetRelativePath: String

    init(file: ArchiveFile, assetRelativePath: String? = nil) {
        self.file = file
        self.assetRelativePath = assetRelativePath
            ?? ArchiveBackupPackage.assetRelativePath(for: file.id)
    }
}

enum ArchiveBackupPackage {
    /// Short enough to survive being shown. `archiveleafbackup` was seventeen characters and got
    /// truncated wherever a name is given a column, which is where a reader looks to tell one
    /// backup from another.
    static let pathExtension = "albak"
    static let manifestFileName = "manifest.json"
    static let assetsDirectoryName = "Assets"

    static func assetRelativePath(for fileID: UUID) -> String {
        "\(assetsDirectoryName)/\(fileID.uuidString.lowercased()).data"
    }

    /// Stamped with the user's own clock rather than UTC. `.iso8601` defaults to GMT, which named a
    /// morning export east of Greenwich after the previous day.
    ///
    /// Held to one line without spaces, and carrying the minute: two exports on one day are the
    /// ordinary case, and a name that stops at the day makes the second one a duplicate the save
    /// panel has to disambiguate. Fields are fixed width and unlocalized, so the name sorts
    /// chronologically as text wherever it is listed.
    static func defaultFileName(on date: Date = .now, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "ArchiveLeaf-Backup-%04d-%02d-%02d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
    }
}
