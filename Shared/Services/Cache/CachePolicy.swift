import Foundation

struct CachePolicy: Sendable {
    let maximumSize: Int64

    static func standard(for platform: Platform) -> CachePolicy {
        switch platform {
        case .macOS:
            CachePolicy(maximumSize: 2 * 1_024 * 1_024 * 1_024)
        case .iPadOS:
            CachePolicy(maximumSize: 1 * 1_024 * 1_024 * 1_024)
        case .iOS:
            CachePolicy(maximumSize: 500 * 1_024 * 1_024)
        }
    }

    enum Platform: Sendable {
        case macOS
        case iPadOS
        case iOS
    }
}
