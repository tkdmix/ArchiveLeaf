import Foundation

enum CloudKitSchema {
    static let containerIdentifier = "iCloud.io.github.inadaman.ArchiveLeaf"

    enum RecordType {
        static let folder = "ArchiveFolder"
        static let file = "ArchiveFile"
        static let tag = "ArchiveTag"
    }

    enum Field {
        static let name = "name"
        static let parentFolder = "parentFolder"
        static let originalParentFolder = "originalParentFolder"
        static let folderSortIndex = "folderSortIndex"
        static let tagIDs = "tagIDs"
        static let isFavorite = "isFavorite"
        static let isTrashed = "isTrashed"
        static let trashedAt = "trashedAt"
        static let originalFileName = "originalFileName"
        static let originalExtension = "originalExtension"
        // Both stored under their former names. The field is what the user called the file;
        // renaming the key would leave every name already chosen behind in a field nothing reads.
        static let userDefinedName = "customDisplayName"
        static let hasUserDefinedName = "hasCustomDisplayName"
        static let detectedFormat = "detectedFormat"
        static let displayFormatOverride = "displayFormatOverride"
        static let sourceEncoding = "sourceEncoding"
        static let sourceEncodingOverride = "sourceEncodingOverride"
        static let sourceModifiedAt = "sourceModifiedAt"
        static let importedAt = "importedAt"
        static let fileSize = "fileSize"
        static let contentHash = "contentHash"
        static let asset = "asset"
        static let imagePixelWidth = "imagePixelWidth"
        static let imagePixelHeight = "imagePixelHeight"
        static let importState = "importState"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    /// Every field a file record carries. Add a new one here as well as to `Field`, or reading the
    /// archive will quietly stop seeing it.
    static let allFileFields = [
        Field.originalFileName, Field.originalExtension, Field.userDefinedName,
        Field.hasUserDefinedName, Field.parentFolder, Field.originalParentFolder, Field.tagIDs,
        Field.isFavorite, Field.isTrashed, Field.trashedAt, Field.detectedFormat,
        Field.displayFormatOverride, Field.sourceEncoding, Field.sourceEncodingOverride,
        Field.sourceModifiedAt, Field.importedAt, Field.fileSize, Field.contentHash,
        Field.asset, Field.imagePixelWidth, Field.imagePixelHeight, Field.importState,
        Field.createdAt, Field.updatedAt
    ]

    /// Everything about a file except the file.
    ///
    /// A query asked for every field is asked for the `CKAsset` too, and CloudKit answers one by
    /// fetching the payload and writing it to disk before the query returns. Every screen in the
    /// app is built from the fields below and none of them from the asset — the asset is read when
    /// something is opened, one file at a time — so a launch that asked for everything downloaded
    /// the entire archive in order to draw a list of names.
    ///
    /// Expressed as a subtraction rather than a list, so that a field added to `allFileFields`
    /// arrives here without anyone remembering to add it.
    static let fileMetadataFields = allFileFields.filter { $0 != Field.asset }
}
