import Foundation
import Darwin

/// Adds disposable work left by older builds or interrupted operations to cache maintenance.
///
/// Some entries predate dedicated ownership, while current preview, backup, and import staging can
/// survive a crash. The cutoff protects work made by this app launch (or a concurrent test run):
/// only entries already present when this cache is made are eligible for removal.
actor ArchiveCacheWithLegacyTemporaryCleanup: ArchiveCaching {
    private let cache: any ArchiveCaching
    private let temporaryDirectoryURL: URL
    private let containerDataDirectoryURL: URL
    private let cutoff: Date
    private let fileManager: FileManager

    init(
        cache: any ArchiveCaching,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        containerDataDirectoryURL: URL? = nil,
        cutoff: Date = .now,
        fileManager: FileManager = .default
    ) {
        self.cache = cache
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.containerDataDirectoryURL = containerDataDirectoryURL ?? temporaryDirectoryURL.deletingLastPathComponent()
        self.cutoff = cutoff
        self.fileManager = fileManager
    }

    func cachedData(for key: String) async throws -> Data? {
        try await cache.cachedData(for: key)
    }

    func store(_ data: Data, for key: String) async throws {
        try await cache.store(data, for: key)
    }

    func removeData(for key: String) async throws {
        try await cache.removeData(for: key)
    }

    func removeAll() async throws {
        try await cache.removeAll()
        for entry in try legacyEntries() {
            try fileManager.removeItem(at: entry.url)
        }
    }

    func currentSize() async throws -> Int64 {
        try await cache.currentSize() + legacyEntries().reduce(0) { $0 + $1.size }
    }

    private func legacyEntries() throws -> [LegacyEntry] {
        try legacyTemporaryEntries() + legacyTemporaryDirectories() + legacyCoverageDirectories()
    }

    private func legacyTemporaryEntries() throws -> [LegacyEntry] {
        guard fileManager.fileExists(atPath: temporaryDirectoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        return try fileManager.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  !isSymbolicLink(at: url),
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff,
                  isLegacyTemporaryFile(url)
            else {
                return nil
            }
            return LegacyEntry(url: url, size: Int64(values.fileSize ?? 0))
        }
    }

    private func legacyTemporaryDirectories() throws -> [LegacyEntry] {
        guard fileManager.fileExists(atPath: temporaryDirectoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]
        return try fileManager.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  !isSymbolicLink(at: url),
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff
            else {
                return nil
            }

            if isLegacyTemporaryDirectory(url) {
                return LegacyEntry(url: url, size: try recursiveFileSize(in: url))
            }
            guard isLegacyTemporaryBackupPackage(url),
                  let size = try legacyTemporaryBackupPackageSize(in: url)
            else {
                return nil
            }
            return LegacyEntry(url: url, size: size)
        }
    }

    private func isLegacyTemporaryDirectory(_ url: URL) -> Bool {
        url.lastPathComponent == "ArchiveLeafPreview"
            || isUUIDNamedDirectory(url, prefix: "ArchiveLeafBackup-")
            || isUUIDNamedDirectory(url, prefix: "ArchiveLeaf-BookmarkImport-")
    }

    private func isLegacyTemporaryBackupPackage(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let prefix = "ArchiveLeaf-"
        let suffix = ".archiveleafbackup"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let identifierStart = name.index(name.startIndex, offsetBy: prefix.count)
        let identifierEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        return isUUIDString(String(name[identifierStart..<identifierEnd]))
    }

    private func isUUIDNamedDirectory(_ url: URL, prefix: String) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix(prefix) else { return false }
        return isUUIDString(String(name.dropFirst(prefix.count)))
    }

    /// A backup package can only be recognised when its root still has the two files the exporter
    /// creates. Other folders with the same extension may be a user's transfer in progress.
    private func legacyTemporaryBackupPackageSize(in directory: URL) throws -> Int64? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        guard contents.count == 2 else { return nil }

        var manifestSize: Int64?
        var assetsURL: URL?
        for url in contents {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, !isSymbolicLink(at: url) else { return nil }
            switch url.lastPathComponent {
            case "manifest.json":
                guard values.isRegularFile == true else { return nil }
                manifestSize = Int64(values.fileSize ?? 0)
            case "Assets":
                guard values.isDirectory == true else { return nil }
                assetsURL = url
            default:
                return nil
            }
        }

        guard let manifestSize, let assetsURL else { return nil }
        return manifestSize + (try recursiveFileSize(in: assetsURL))
    }

    /// Counts files below a recognised directory without following links outside its root.
    private func recursiveFileSize(in directory: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return 0
        }

        var size: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true || isSymbolicLink(at: url) {
                continue
            }
            guard values.isRegularFile == true else { continue }
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }

    private func legacyCoverageDirectories() throws -> [LegacyEntry] {
        guard fileManager.fileExists(atPath: containerDataDirectoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        return try fileManager.contentsOfDirectory(
            at: containerDataDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  !isSymbolicLink(at: url),
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff,
                  isLegacyCoverageDirectory(url)
            else {
                return nil
            }
            guard let contents = try eligibleCoverageContents(in: url) else { return nil }
            let directorySize = Int64(values.fileSize ?? 0)
            return LegacyEntry(url: url, size: directorySize + contents.reduce(0) { $0 + $1 })
        }
    }

    private func isLegacyCoverageDirectory(_ url: URL) -> Bool {
        let components = url.lastPathComponent.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 7 else { return false }
        let uuid = components[0...4].joined(separator: "-")
        guard isUUIDString(uuid),
              !components[5].isEmpty,
              components[5].allSatisfy(\.isWholeNumber),
              !components[6].isEmpty,
              components[6].allSatisfy(\.isHexDigit)
        else {
            return false
        }
        return true
    }

    private func eligibleCoverageContents(in directory: URL) throws -> [Int64]? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        var sizes: [Int64] = []
        for url in contents {
            let values = try url.resourceValues(forKeys: keys)
            guard !url.lastPathComponent.hasPrefix("."),
                  url.pathExtension == "profraw",
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  !isSymbolicLink(at: url)
            else {
                return nil
            }
            sizes.append(Int64(values.fileSize ?? 0))
        }
        return sizes
    }

    private func isLegacyTemporaryFile(_ url: URL) -> Bool {
        guard Self.knownExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let name = url.deletingPathExtension().lastPathComponent
        return isUUIDString(name)
    }

    private func isUUIDString(_ name: String) -> Bool {
        guard name.count == 36, UUID(uuidString: name) != nil else { return false }
        let hyphenOffsets = [8, 13, 18, 23]
        return name.enumerated().allSatisfy { index, character in
            if hyphenOffsets.contains(index) { return character == "-" }
            return character.isHexDigit
        }
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        var fileStatus = stat()
        return lstat(url.path, &fileStatus) == 0 && (fileStatus.st_mode & S_IFMT) == S_IFLNK
    }

    private static let knownExtensions: Set<String> = [
        "txt", "json", "png", "csv", "webloc", "jpg", "jpeg", "md", "markdown",
        "mp4", "m4v", "mov", "data"
    ]
}

private struct LegacyEntry {
    let url: URL
    let size: Int64
}
