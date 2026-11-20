import Foundation
import ImageIO

struct RepositoryFileContentLoader: FileContentLoading {
    private let repository: any ArchiveRepository
    private let cache: (any ArchiveCaching)?
    private let maximumTextDisplaySize: Int64
    private let maximumRichTextDisplaySize: Int64
    private let maximumImageDisplaySize: Int64
    private let maximumVideoDisplaySize: Int64
    private let maximumPDFDisplaySize: Int64
    private let videoPlaybackFiles: VideoPlaybackFileStore

    init(
        repository: any ArchiveRepository,
        cache: (any ArchiveCaching)? = nil,
        maximumTextDisplaySize: Int64 = ImportPolicy().maximumTextDisplaySize,
        maximumRichTextDisplaySize: Int64 = ImportPolicy().maximumRichTextDisplaySize,
        maximumImageDisplaySize: Int64 = ImportPolicy().maximumImageSize,
        maximumVideoDisplaySize: Int64 = ImportPolicy().maximumVideoSize,
        maximumPDFDisplaySize: Int64 = ImportPolicy().maximumPDFSize,
        videoPlaybackFiles: VideoPlaybackFileStore = VideoPlaybackFileStore()
    ) {
        self.repository = repository
        self.cache = cache
        self.maximumTextDisplaySize = maximumTextDisplaySize
        self.maximumRichTextDisplaySize = maximumRichTextDisplaySize
        self.maximumImageDisplaySize = maximumImageDisplaySize
        self.maximumVideoDisplaySize = maximumVideoDisplaySize
        self.maximumPDFDisplaySize = maximumPDFDisplaySize
        self.videoPlaybackFiles = videoPlaybackFiles
    }

    func loadContent(for file: ArchiveFile) async throws -> LoadedFileContent {
        let displayLimit = if file.effectiveDisplayFormat.isImage {
            maximumImageDisplaySize
        } else if file.effectiveDisplayFormat.isVideo {
            maximumVideoDisplaySize
        } else if file.effectiveDisplayFormat.isPDF {
            maximumPDFDisplaySize
        } else {
            maximumTextDisplaySize
        }
        guard file.fileSize <= displayLimit else {
            throw FileContentLoadingError.displaySizeExceeded(displayLimit)
        }

        // AVPlayer streams from a file URL. Keeping video out of Data and the document cache avoids
        // copying the whole movie into memory before playback starts. A CKAsset download URL is
        // temporary, so give the player an owned copy whose lifetime the view can control.
        if file.effectiveDisplayFormat.isVideo {
            let sourceURL = try await repository.fileContentURL(for: file.id)
            return .video(LoadedVideoContent(url: try videoPlaybackFiles.copy(of: sourceURL, for: file)))
        }

        let cacheKey = cacheKey(for: file)
        if let cache, let cachedData = try? await cache.cachedData(for: cacheKey) {
            do {
                return try loadedContent(from: cachedData, for: file)
            } catch {
                try? await cache.removeData(for: cacheKey)
            }
        }

        let data = try await fetchAndCache(file, cacheKey: cacheKey)
        return try loadedContent(from: data, for: file)
    }

    /// No display limit: the limits are about what can be drawn on screen, and handing the file to
    /// another app draws nothing.
    func originalData(for file: ArchiveFile) async throws -> Data {
        let cacheKey = cacheKey(for: file)
        if let cache, let cachedData = try? await cache.cachedData(for: cacheKey) {
            return cachedData
        }
        return try await fetchAndCache(file, cacheKey: cacheKey)
    }

    private func cacheKey(for file: ArchiveFile) -> String {
        file.contentHash.isEmpty ? file.id.uuidString : file.contentHash
    }

}

/// Owns only the disposable files AVPlayer needs after CloudKit's CKAsset URL goes away.
///
/// Normal navigation removes the active file from the detail view. Removing the whole dedicated
/// directory at launch also covers a crash or forced termination without touching the archive
/// cache, imported files, or any other process's temporary data.
struct VideoPlaybackFileStore: Sendable {
    private let directoryURL: URL

    init(
        directoryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeaf-VideoPlayback", isDirectory: true)
    ) {
        self.directoryURL = directoryURL
    }

    func copy(of sourceURL: URL, for file: ArchiveFile) throws -> URL {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let pathExtension = file.originalExtension
                ?? (file.effectiveDisplayFormat == .mov ? "mov" : "mp4")
            let destination = directoryURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(pathExtension)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            throw ArchiveLeafError.unreadableFile
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private extension RepositoryFileContentLoader {

    private func fetchAndCache(_ file: ArchiveFile, cacheKey: String) async throws -> Data {
        let url = try await repository.fileContentURL(for: file.id)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try? await cache?.store(data, for: cacheKey)
        return data
    }

    private func loadedContent(from data: Data, for file: ArchiveFile) throws -> LoadedFileContent {
        if file.effectiveDisplayFormat == .bookmark {
            return .bookmark(try BookmarkDocument.url(from: data))
        }
        if file.effectiveDisplayFormat.isImage {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ArchiveLeafError.corruptedFile
            }
            // As the picture is shown, not as its pixels are stored: a photograph taken upright
            // keeps landscape pixels and an orientation tag, and every viewer applies the tag. The
            // stored numbers would size the frame across the picture's short side and flatten it.
            let upright = displayedSize(width: image.width, height: image.height, in: source)
            return .image(LoadedImageContent(
                data: data,
                pixelWidth: upright.width,
                pixelHeight: upright.height
            ))
        }

        // Handed on as its imported bytes. PDFKit reads the document itself, so nothing here
        // decodes, re-encodes, or renders it.
        if file.effectiveDisplayFormat.isPDF {
            return .pdf(data)
        }

        guard let text = (file.effectiveTextEncoding ?? .utf8).decode(data) else {
            throw ArchiveLeafError.unreadableFile
        }

        switch file.effectiveDisplayFormat {
        case .plainText:
            return .plainText(text)
        case .markdown:
            guard file.fileSize <= maximumRichTextDisplaySize else {
                return .plainText(text)
            }
            return .markdown(text)
        case .json:
            guard file.fileSize <= maximumRichTextDisplaySize else {
                return .plainText(text)
            }
            return .json(try prettyPrintedJSON(data))
        case .csv:
            // Compatibility for records imported before CSV-specific presentation was retired.
            return .plainText(text)
        case .jpeg, .png, .bookmark, .mp4, .mov, .pdf:
            throw ArchiveLeafError.unsupportedFormat
        }
    }

    /// The side lengths after the orientation tag is applied. The four quarter-turn orientations
    /// exchange the two; the rest, including a missing or unreadable tag, leave them alone.
    private func displayedSize(
        width: Int,
        height: Int,
        in source: CGImageSource
    ) -> (width: Int, height: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    private func prettyPrintedJSON(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        guard let text = String(data: prettyData, encoding: .utf8) else {
            throw ArchiveLeafError.unreadableFile
        }
        return text
    }
}

enum FileContentLoadingError: LocalizedError {
    case displaySizeExceeded(Int64)

    var errorDescription: String? {
        switch self {
        case .displaySizeExceeded(let limit):
            "The file exceeds the \(limit.formatted(.byteCount(style: .file))) display limit."
        }
    }
}
