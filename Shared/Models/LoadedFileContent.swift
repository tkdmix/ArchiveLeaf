import Foundation

struct LoadedImageContent: Equatable, Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

struct LoadedVideoContent: Equatable, Sendable {
    /// A playback-owned copy. CloudKit's downloaded CKAsset URL is temporary and must not be held
    /// by AVPlayer after the record that supplied it has gone away.
    let url: URL
}

enum LoadedFileContent: Equatable, Sendable {
    case plainText(String)
    case markdown(String)
    case json(String)
    case image(LoadedImageContent)
    case bookmark(URL)
    case video(LoadedVideoContent)
    case pdf(Data)
}
