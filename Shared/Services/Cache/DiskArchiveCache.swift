import CryptoKit
import Foundation

actor DiskArchiveCache: ArchiveCaching {
    private let directoryURL: URL
    private let policy: CachePolicy
    private let fileManager: FileManager

    init(
        directoryURL: URL,
        policy: CachePolicy,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.policy = policy
        self.fileManager = fileManager
    }

    func cachedData(for key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return data
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func store(_ data: Data, for key: String) throws {
        guard Int64(data.count) <= policy.maximumSize else { return }
        try createDirectoryIfNeeded()
        try data.write(to: fileURL(for: key), options: .atomic)
        try evictIfNeeded()
    }

    func removeData(for key: String) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    func currentSize() throws -> Int64 {
        try entries().reduce(0) { $0 + $1.size }
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func evictIfNeeded() throws {
        var cachedEntries = try entries().sorted { $0.lastAccessed < $1.lastAccessed }
        var size = cachedEntries.reduce(0) { $0 + $1.size }
        while size > policy.maximumSize, !cachedEntries.isEmpty {
            let oldest = cachedEntries.removeFirst()
            try fileManager.removeItem(at: oldest.url)
            size -= oldest.size
        }
    }

    private func entries() throws -> [CacheEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            return CacheEntry(
                url: url,
                size: Int64(values.fileSize ?? 0),
                lastAccessed: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent(digest, isDirectory: false)
    }
}

private struct CacheEntry {
    let url: URL
    let size: Int64
    let lastAccessed: Date
}
