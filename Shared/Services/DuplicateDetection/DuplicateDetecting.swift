import Foundation

protocol DuplicateDetecting: Sendable {
    func contentHash(for url: URL) async throws -> String
    /// The archived files matching any of these hashes, keyed by lowercased hash.
    func existingFiles(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile]
}

/// Searches completed files, including files currently in the app trash.
///
/// Asked about a whole import rather than one file at a time. Where the archive is a service, one
/// question about twenty-four files is one round trip and twenty-four questions are twenty-four —
/// measured at about 550 ms each, which is most of what an import used to spend before it wrote
/// anything at all.
protocol DuplicateFileLookingUp: Sendable {
    func files(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile]
}
