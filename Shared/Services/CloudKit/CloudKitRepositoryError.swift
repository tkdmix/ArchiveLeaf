import Foundation

enum CloudKitRepositoryError: LocalizedError {
    case invalidRecordID(String)
    case missingRequiredField(String)
    case invalidFieldValue(String)
    case missingAsset
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRecordID(let value):
            "The CloudKit record ID is not a valid ArchiveLeaf ID: \(value)"
        case .missingRequiredField(let field):
            "The CloudKit record is missing the required field: \(field)"
        case .invalidFieldValue(let field):
            "The CloudKit record contains an invalid value for: \(field)"
        case .missingAsset:
            "The file asset is not available locally."
        case .iCloudUnavailable:
            "iCloud is not available for this account."
        }
    }
}
