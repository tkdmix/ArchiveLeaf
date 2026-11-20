import Foundation

enum ImportState: String, Codable, Sendable {
    case preparing
    case reading
    case detecting
    case extracting
    case hashing
    case uploading
    case completed
    case failed
}
