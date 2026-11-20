import Foundation

/// Detects a supported viewing format without modifying the source content.
protocol FileFormatDetecting: Sendable {
    func detectFormat(for url: URL) async throws -> FileDetectionResult
}

enum FileDetectionResult: Equatable, Sendable {
    case viewable(format: ImportedFormat, sourceEncoding: String?)
    case zipArchive
}
