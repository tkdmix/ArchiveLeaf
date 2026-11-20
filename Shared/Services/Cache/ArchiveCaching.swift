import Foundation

/// Stores disposable derived data such as thumbnails or rendered previews.
protocol ArchiveCaching: Sendable {
    func cachedData(for key: String) async throws -> Data?
    func store(_ data: Data, for key: String) async throws
    func removeData(for key: String) async throws
    func removeAll() async throws
    func currentSize() async throws -> Int64
}
