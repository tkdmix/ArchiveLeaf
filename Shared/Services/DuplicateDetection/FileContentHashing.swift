import CryptoKit
import Foundation

protocol FileContentHashing: Sendable {
    func sha256(for url: URL) async throws -> String
}

struct SHA256FileContentHasher: FileContentHashing {
    private static let readChunkSize = 1_024 * 1_024

    func sha256(for url: URL) async throws -> String {
        guard url.isFileURL else { throw ArchiveLeafError.unreadableFile }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ArchiveLeafError.unreadableFile
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let data = try autoreleasepool(invoking: { try handle.read(upToCount: Self.readChunkSize) }), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ArchiveLeafError.unreadableFile
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
