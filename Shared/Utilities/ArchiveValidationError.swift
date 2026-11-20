import Foundation

enum ArchiveValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case missingParent
    case cyclicFolderReference

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "A name cannot be empty."
        case .duplicateName:
            "An item with the same name already exists in this folder."
        case .missingParent:
            "The destination folder does not exist."
        case .cyclicFolderReference:
            "A folder cannot be moved into itself or one of its descendants."
        }
    }
}
