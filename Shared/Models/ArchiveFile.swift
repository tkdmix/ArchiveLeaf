import Foundation

struct ArchiveFile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let originalFileName: String
    let originalExtension: String?
    var userDefinedName: String?
    var parentFolderID: UUID?
    var originalParentFolderID: UUID?
    /// The tags put on this file. Held here rather than in a record of their own: a file is saved
    /// as one thing, and a tag's name lives in the tag, so renaming one touches no files.
    var tagIDs: [UUID]
    var isFavorite: Bool
    var isTrashed: Bool
    var trashedAt: Date?
    let detectedFormat: ImportedFormat
    var displayFormatOverride: ImportedFormat?
    let sourceEncoding: String?
    var sourceEncodingOverride: ArchiveTextEncoding?
    let sourceModifiedAt: Date?
    let importedAt: Date
    let fileSize: Int64
    let contentHash: String
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    var importState: ImportState
    let createdAt: Date
    var updatedAt: Date

    /// Written out by the synthesized encoder; read back by hand for one field alone.
    ///
    /// A backup made before tags existed has no `tagIDs` key, and the synthesized decoder treats a
    /// missing key as a failure — which would have made every archive exported until now
    /// unreadable. Nothing else here is allowed to be absent.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalFileName = try container.decode(String.self, forKey: .originalFileName)
        originalExtension = try container.decodeIfPresent(String.self, forKey: .originalExtension)
        userDefinedName = try container.decodeIfPresent(String.self, forKey: .userDefinedName)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        originalParentFolderID = try container.decodeIfPresent(UUID.self, forKey: .originalParentFolderID)
        tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        isTrashed = try container.decode(Bool.self, forKey: .isTrashed)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        detectedFormat = try container.decode(ImportedFormat.self, forKey: .detectedFormat)
        displayFormatOverride = try container.decodeIfPresent(ImportedFormat.self, forKey: .displayFormatOverride)
        sourceEncoding = try container.decodeIfPresent(String.self, forKey: .sourceEncoding)
        sourceEncodingOverride = try container.decodeIfPresent(ArchiveTextEncoding.self, forKey: .sourceEncodingOverride)
        sourceModifiedAt = try container.decodeIfPresent(Date.self, forKey: .sourceModifiedAt)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        imagePixelWidth = try container.decodeIfPresent(Int.self, forKey: .imagePixelWidth)
        imagePixelHeight = try container.decodeIfPresent(Int.self, forKey: .imagePixelHeight)
        importState = try container.decode(ImportState.self, forKey: .importState)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Whether the file has been renamed since it arrived.
    var hasUserDefinedName: Bool {
        guard let userDefinedName else { return false }
        return !userDefinedName.isEmpty
    }

    /// What the file is called: what the user named it, or what it arrived as.
    ///
    /// One name, not two. `originalFileName` is kept as a record of what came in and is shown only
    /// where it differs from this — nothing lists or orders by it.
    var displayName: String {
        userDefinedName ?? originalFileName.deletingPathExtension
    }

    var sidebarDisplayName: String {
        if detectedFormat == .bookmark { return displayName }
        guard let originalExtension, !originalExtension.isEmpty else { return displayName }
        return "\(displayName).\(originalExtension)"
    }

    var effectiveDisplayFormat: ImportedFormat {
        displayFormatOverride ?? detectedFormat
    }

    var effectiveTextEncoding: ArchiveTextEncoding? {
        sourceEncodingOverride ?? ArchiveTextEncoding.named(sourceEncoding)
    }

    init(
        id: UUID = UUID(),
        originalFileName: String,
        originalExtension: String? = nil,
        userDefinedName: String? = nil,
        parentFolderID: UUID? = nil,
        originalParentFolderID: UUID? = nil,
        tagIDs: [UUID] = [],
        isFavorite: Bool = false,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        detectedFormat: ImportedFormat,
        displayFormatOverride: ImportedFormat? = nil,
        sourceEncoding: String? = nil,
        sourceEncodingOverride: ArchiveTextEncoding? = nil,
        sourceModifiedAt: Date? = nil,
        importedAt: Date = .now,
        fileSize: Int64 = 0,
        contentHash: String = "",
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        importState: ImportState = .completed,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.originalExtension = originalExtension ?? originalFileName.pathExtension
        self.userDefinedName = userDefinedName
        self.parentFolderID = parentFolderID
        self.originalParentFolderID = originalParentFolderID
        self.tagIDs = tagIDs
        self.isFavorite = isFavorite
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.detectedFormat = detectedFormat
        self.displayFormatOverride = displayFormatOverride
        self.sourceEncoding = sourceEncoding
        self.sourceEncodingOverride = sourceEncodingOverride
        self.sourceModifiedAt = sourceModifiedAt
        self.importedAt = importedAt
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.importState = importState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private extension String {
    var pathExtension: String? {
        let value = (self as NSString).pathExtension
        return value.isEmpty ? nil : value
    }

    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
