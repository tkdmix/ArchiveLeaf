import Foundation

enum ArchiveLeafError: LocalizedError, Equatable {
    case notImplemented
    case unsupportedFormat
    case unreadableFile
    case corruptedFile

    var errorDescription: String? {
        switch self {
        case .notImplemented: "This feature is not implemented yet."
        case .unsupportedFormat: "The file format is not supported."
        case .unreadableFile: "The file could not be read."
        case .corruptedFile: "The file is damaged or has invalid content."
        }
    }
}
