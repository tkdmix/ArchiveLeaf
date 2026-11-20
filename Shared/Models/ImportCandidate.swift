import Foundation

struct ImportCandidate: Sendable {
    let sourceURL: URL
    let detection: FileDetectionResult
    let fileSize: Int64
    let sourceModifiedAt: Date?
    let contentHash: String
    var relativePathComponents: [String]? = nil

    var importPathComponents: [String] {
        relativePathComponents ?? [sourceURL.lastPathComponent]
    }
}

struct ImportPreflightResult: Sendable {
    let candidates: [ImportCandidate]
    let failures: [ImportFailure]
    var folderPathComponents: [[String]] = []
    var temporaryDirectoryURLs: [URL] = []
}
