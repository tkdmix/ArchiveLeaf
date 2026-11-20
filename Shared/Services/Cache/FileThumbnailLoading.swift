import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

protocol FileThumbnailLoading: Sendable {
    func loadThumbnail(for file: ArchiveFile) async throws -> Data?
}

/// The small picture a row shows for a file it can draw one for.
///
/// A picture is its own thumbnail, scaled down. A PDF has none stored, so its first page is drawn.
/// Everything else keeps its symbol: a movie deliberately has no thumbnail, because generating one
/// would mean fetching and decoding the movie to fill a 28-point square.
struct FileThumbnailLoader: FileThumbnailLoading {
    private let contentLoader: any FileContentLoading
    private let cache: (any ArchiveCaching)?
    private let maximumPixelSize: Int

    init(
        contentLoader: any FileContentLoading,
        cache: (any ArchiveCaching)? = nil,
        maximumPixelSize: Int = 96
    ) {
        self.contentLoader = contentLoader
        self.cache = cache
        self.maximumPixelSize = maximumPixelSize
    }

    func loadThumbnail(for file: ArchiveFile) async throws -> Data? {
        let format = file.effectiveDisplayFormat
        guard format.isImage || format.isPDF else { return nil }

        let sourceKey = file.contentHash.isEmpty ? file.id.uuidString : file.contentHash
        let cacheKey = "thumbnail-v1-\(maximumPixelSize)-\(sourceKey)"
        if let cached = try? await cache?.cachedData(for: cacheKey) {
            return cached
        }

        let content = try await contentLoader.loadContent(for: file)
        let thumbnail: Data
        switch content {
        case .image(let image):
            thumbnail = try makeThumbnail(from: image.data)
        case .pdf(let data):
            thumbnail = try makeFirstPageThumbnail(from: data)
        default:
            return nil
        }
        try? await cache?.store(thumbnail, for: cacheKey)
        return thumbnail
    }

    private func makeThumbnail(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
              ) else {
            throw ArchiveLeafError.corruptedFile
        }
        return try pngData(from: image)
    }

    /// The first page, drawn onto white.
    ///
    /// A page is paper: its own drawing assumes something opaque behind it, and text drawn in black
    /// onto a transparent square disappears in a dark row. The crop box is what a reader is meant
    /// to see, and the drawing transform applies the page's own rotation.
    private func makeFirstPageThumbnail(from data: Data) throws -> Data {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            throw ArchiveLeafError.corruptedFile
        }

        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { throw ArchiveLeafError.corruptedFile }
        let isQuarterTurned = (page.rotationAngle / 90) % 2 != 0
        let visibleSize = isQuarterTurned
            ? CGSize(width: box.height, height: box.width)
            : box.size
        let scale = CGFloat(maximumPixelSize) / max(visibleSize.width, visibleSize.height)
        let width = max(Int((visibleSize.width * scale).rounded()), 1)
        let height = max(Int((visibleSize.height * scale).rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ArchiveLeafError.corruptedFile
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.concatenate(page.getDrawingTransform(
            .cropBox,
            rect: bounds,
            rotate: 0,
            preserveAspectRatio: true
        ))
        context.drawPDFPage(page)

        guard let image = context.makeImage() else { throw ArchiveLeafError.corruptedFile }
        return try pngData(from: image)
    }

    private func pngData(from image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ArchiveLeafError.corruptedFile
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ArchiveLeafError.corruptedFile
        }
        return output as Data
    }
}
