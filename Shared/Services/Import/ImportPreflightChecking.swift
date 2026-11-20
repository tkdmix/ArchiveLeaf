import Foundation

/// Validates selected source files without modifying or copying them.
protocol ImportPreflightChecking: Sendable {
    func inspect(urls: [URL]) async -> ImportPreflightResult
}
