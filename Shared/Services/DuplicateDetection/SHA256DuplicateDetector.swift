import Foundation

struct SHA256DuplicateDetector: DuplicateDetecting {
    private let lookup: any DuplicateFileLookingUp
    private let hasher: any FileContentHashing

    init(
        lookup: any DuplicateFileLookingUp,
        hasher: any FileContentHashing = SHA256FileContentHasher()
    ) {
        self.lookup = lookup
        self.hasher = hasher
    }

    func contentHash(for url: URL) async throws -> String {
        try await hasher.sha256(for: url)
    }

    func existingFiles(matchingContentHashes hashes: Set<String>) async throws -> [String: ArchiveFile] {
        let normalized = Set(hashes.filter { !$0.isEmpty }.map { $0.lowercased() })
        guard !normalized.isEmpty else { return [:] }
        return try await lookup.files(matchingContentHashes: normalized)
    }
}
