@preconcurrency import CloudKit
import Foundation

enum CloudKitRecordMapper {
    static func record(from folder: ArchiveFolder) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.folder,
            recordID: recordID(for: folder.id)
        )
        update(record, from: folder)
        return record
    }

    static func update(_ record: CKRecord, from folder: ArchiveFolder) {
        record[CloudKitSchema.Field.name] = folder.name as CKRecordValue
        record[CloudKitSchema.Field.parentFolder] = reference(for: folder.parentFolderID)
        record[CloudKitSchema.Field.originalParentFolder] = reference(for: folder.originalParentFolderID)
        record[CloudKitSchema.Field.folderSortIndex] = folder.folderSortIndex as CKRecordValue
        record[CloudKitSchema.Field.isTrashed] = folder.isTrashed as CKRecordValue
        record[CloudKitSchema.Field.trashedAt] = folder.trashedAt as CKRecordValue?
        record[CloudKitSchema.Field.createdAt] = folder.createdAt as CKRecordValue
        record[CloudKitSchema.Field.updatedAt] = folder.updatedAt as CKRecordValue
    }

    static func folder(from record: CKRecord) throws -> ArchiveFolder {
        let id = try archiveID(from: record)
        return ArchiveFolder(
            id: id,
            name: try requiredString(CloudKitSchema.Field.name, in: record),
            parentFolderID: try referencedArchiveID(CloudKitSchema.Field.parentFolder, in: record),
            originalParentFolderID: try referencedArchiveID(CloudKitSchema.Field.originalParentFolder, in: record),
            folderSortIndex: integer(CloudKitSchema.Field.folderSortIndex, in: record) ?? 0,
            isTrashed: boolean(CloudKitSchema.Field.isTrashed, in: record),
            trashedAt: record[CloudKitSchema.Field.trashedAt] as? Date,
            createdAt: date(CloudKitSchema.Field.createdAt, in: record) ?? record.creationDate ?? .now,
            updatedAt: date(CloudKitSchema.Field.updatedAt, in: record) ?? record.modificationDate ?? .now
        )
    }

    static func record(from file: ArchiveFile, assetURL: URL? = nil) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.file,
            recordID: recordID(for: file.id)
        )
        update(record, from: file, assetURL: assetURL)
        return record
    }

    static func update(_ record: CKRecord, from file: ArchiveFile, assetURL: URL? = nil) {
        record[CloudKitSchema.Field.originalFileName] = file.originalFileName as CKRecordValue
        record[CloudKitSchema.Field.originalExtension] = file.originalExtension as CKRecordValue?
        record[CloudKitSchema.Field.userDefinedName] = file.userDefinedName as CKRecordValue?
        record[CloudKitSchema.Field.hasUserDefinedName] = file.hasUserDefinedName as CKRecordValue
        record[CloudKitSchema.Field.parentFolder] = reference(for: file.parentFolderID)
        record[CloudKitSchema.Field.originalParentFolder] = reference(for: file.originalParentFolderID)
        record[CloudKitSchema.Field.tagIDs] = file.tagIDs.map(\.uuidString) as CKRecordValue
        record[CloudKitSchema.Field.isFavorite] = file.isFavorite as CKRecordValue
        record[CloudKitSchema.Field.isTrashed] = file.isTrashed as CKRecordValue
        record[CloudKitSchema.Field.trashedAt] = file.trashedAt as CKRecordValue?
        record[CloudKitSchema.Field.detectedFormat] = file.detectedFormat.rawValue as CKRecordValue
        record[CloudKitSchema.Field.displayFormatOverride] = file.displayFormatOverride?.rawValue as CKRecordValue?
        record[CloudKitSchema.Field.sourceEncoding] = file.sourceEncoding as CKRecordValue?
        record[CloudKitSchema.Field.sourceEncodingOverride] = file.sourceEncodingOverride?.rawValue as CKRecordValue?
        record[CloudKitSchema.Field.sourceModifiedAt] = file.sourceModifiedAt as CKRecordValue?
        record[CloudKitSchema.Field.importedAt] = file.importedAt as CKRecordValue
        record[CloudKitSchema.Field.fileSize] = file.fileSize as CKRecordValue
        record[CloudKitSchema.Field.contentHash] = file.contentHash as CKRecordValue
        record[CloudKitSchema.Field.imagePixelWidth] = file.imagePixelWidth as CKRecordValue?
        record[CloudKitSchema.Field.imagePixelHeight] = file.imagePixelHeight as CKRecordValue?
        record[CloudKitSchema.Field.importState] = file.importState.rawValue as CKRecordValue
        record[CloudKitSchema.Field.createdAt] = file.createdAt as CKRecordValue
        record[CloudKitSchema.Field.updatedAt] = file.updatedAt as CKRecordValue
        if let assetURL {
            record[CloudKitSchema.Field.asset] = CKAsset(fileURL: assetURL)
        }
    }

    static func tag(from record: CKRecord) throws -> ArchiveTag {
        ArchiveTag(
            id: try archiveID(from: record),
            name: try requiredString(CloudKitSchema.Field.name, in: record),
            createdAt: record.creationDate ?? .now,
            updatedAt: record.modificationDate ?? .now
        )
    }

    static func update(_ record: CKRecord, from tag: ArchiveTag) {
        record[CloudKitSchema.Field.name] = tag.name as CKRecordValue
    }

    static func file(from record: CKRecord) throws -> ArchiveFile {
        let id = try archiveID(from: record)
        let formatValue = try requiredString(CloudKitSchema.Field.detectedFormat, in: record)
        guard let detectedFormat = ImportedFormat(rawValue: formatValue) else {
            throw CloudKitRepositoryError.invalidFieldValue(CloudKitSchema.Field.detectedFormat)
        }

        let overrideValue = record[CloudKitSchema.Field.displayFormatOverride] as? String
        let displayFormatOverride = try overrideValue.map {
            guard let format = ImportedFormat(rawValue: $0) else {
                throw CloudKitRepositoryError.invalidFieldValue(CloudKitSchema.Field.displayFormatOverride)
            }
            return format
        }

        let encodingOverrideValue = record[CloudKitSchema.Field.sourceEncodingOverride] as? String
        let sourceEncodingOverride = try encodingOverrideValue.map {
            guard let encoding = ArchiveTextEncoding(rawValue: $0) else {
                throw CloudKitRepositoryError.invalidFieldValue(CloudKitSchema.Field.sourceEncodingOverride)
            }
            return encoding
        }

        return ArchiveFile(
            id: id,
            originalFileName: try requiredString(CloudKitSchema.Field.originalFileName, in: record),
            originalExtension: record[CloudKitSchema.Field.originalExtension] as? String,
            userDefinedName: record[CloudKitSchema.Field.userDefinedName] as? String,
            parentFolderID: try referencedArchiveID(CloudKitSchema.Field.parentFolder, in: record),
            originalParentFolderID: try referencedArchiveID(CloudKitSchema.Field.originalParentFolder, in: record),
            tagIDs: (record[CloudKitSchema.Field.tagIDs] as? [String] ?? [])
                .compactMap(UUID.init(uuidString:)),
            isFavorite: boolean(CloudKitSchema.Field.isFavorite, in: record),
            isTrashed: boolean(CloudKitSchema.Field.isTrashed, in: record),
            trashedAt: record[CloudKitSchema.Field.trashedAt] as? Date,
            detectedFormat: detectedFormat,
            displayFormatOverride: displayFormatOverride,
            sourceEncoding: record[CloudKitSchema.Field.sourceEncoding] as? String,
            sourceEncodingOverride: sourceEncodingOverride,
            sourceModifiedAt: record[CloudKitSchema.Field.sourceModifiedAt] as? Date,
            importedAt: date(CloudKitSchema.Field.importedAt, in: record) ?? .now,
            fileSize: int64(CloudKitSchema.Field.fileSize, in: record) ?? 0,
            contentHash: try requiredString(CloudKitSchema.Field.contentHash, in: record),
            imagePixelWidth: integer(CloudKitSchema.Field.imagePixelWidth, in: record),
            imagePixelHeight: integer(CloudKitSchema.Field.imagePixelHeight, in: record),
            importState: ImportState(
                rawValue: record[CloudKitSchema.Field.importState] as? String ?? ""
            ) ?? .completed,
            createdAt: date(CloudKitSchema.Field.createdAt, in: record) ?? record.creationDate ?? .now,
            updatedAt: date(CloudKitSchema.Field.updatedAt, in: record) ?? record.modificationDate ?? .now
        )
    }

    private static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    private static func reference(for id: UUID?) -> CKRecord.Reference? {
        id.map { CKRecord.Reference(recordID: recordID(for: $0), action: .none) }
    }

    private static func archiveID(from record: CKRecord) throws -> UUID {
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw CloudKitRepositoryError.invalidRecordID(record.recordID.recordName)
        }
        return id
    }

    private static func referencedArchiveID(_ field: String, in record: CKRecord) throws -> UUID? {
        guard let reference = record[field] as? CKRecord.Reference else { return nil }
        guard let id = UUID(uuidString: reference.recordID.recordName) else {
            throw CloudKitRepositoryError.invalidRecordID(reference.recordID.recordName)
        }
        return id
    }

    private static func requiredString(_ field: String, in record: CKRecord) throws -> String {
        guard let value = record[field] as? String else {
            throw CloudKitRepositoryError.missingRequiredField(field)
        }
        return value
    }

    private static func boolean(_ field: String, in record: CKRecord) -> Bool {
        (record[field] as? NSNumber)?.boolValue ?? false
    }

    private static func integer(_ field: String, in record: CKRecord) -> Int? {
        (record[field] as? NSNumber)?.intValue
    }

    private static func int64(_ field: String, in record: CKRecord) -> Int64? {
        (record[field] as? NSNumber)?.int64Value
    }

    private static func date(_ field: String, in record: CKRecord) -> Date? {
        record[field] as? Date
    }
}
