import Foundation
import ImageIO
import XCTest
@testable import ArchiveLeaf

final class FileThumbnailLoaderTests: XCTestCase {
    func testCreatesThumbnailAndReusesCachedResult() async throws {
        let sourceData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let contentLoader = ThumbnailContentLoader(
            content: .image(LoadedImageContent(data: sourceData, pixelWidth: 1, pixelHeight: 1))
        )
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskArchiveCache(
            directoryURL: directory,
            policy: CachePolicy(maximumSize: 100_000)
        )
        let loader = FileThumbnailLoader(
            contentLoader: contentLoader,
            cache: cache,
            maximumPixelSize: 48
        )
        let file = ArchiveFile(
            originalFileName: "leaf.png",
            detectedFormat: .png,
            contentHash: "image-hash"
        )

        let firstResult = try await loader.loadThumbnail(for: file)
        let secondResult = try await loader.loadThumbnail(for: file)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)
        let loadCount = await contentLoader.loadCount

        XCTAssertEqual(first, second)
        XCTAssertEqual(loadCount, 1)
        XCTAssertNotNil(CGImageSourceCreateWithData(first as CFData, nil))
    }

    func testSkipsNonImageWithoutLoadingContent() async throws {
        let contentLoader = ThumbnailContentLoader(content: .plainText(""))
        let loader = FileThumbnailLoader(contentLoader: contentLoader)
        let file = ArchiveFile(
            originalFileName: "leaf.txt",
            detectedFormat: .plainText
        )

        let thumbnail = try await loader.loadThumbnail(for: file)

        let loadCount = await contentLoader.loadCount
        XCTAssertNil(thumbnail)
        XCTAssertEqual(loadCount, 0)
    }

    func testDrawsTheFirstPageOfAPDFPreservingItsShape() async throws {
        let contentLoader = ThumbnailContentLoader(
            content: .pdf(PDFTestDocument.data(width: 200, height: 400))
        )
        let loader = FileThumbnailLoader(contentLoader: contentLoader, maximumPixelSize: 48)
        let file = ArchiveFile(
            originalFileName: "leaf.pdf",
            detectedFormat: .pdf,
            contentHash: "pdf-hash"
        )

        let result = try await loader.loadThumbnail(for: file)
        let thumbnail = try XCTUnwrap(result)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // The taller side is what the limit applies to, and the page is twice as tall as it is wide.
        XCTAssertEqual(image.height, 48)
        XCTAssertEqual(image.width, 24)
    }

    func testSkipsVideoWithoutLoadingContent() async throws {
        let contentLoader = ThumbnailContentLoader(content: .plainText(""))
        let loader = FileThumbnailLoader(contentLoader: contentLoader)
        let file = ArchiveFile(originalFileName: "leaf.mp4", detectedFormat: .mp4)

        let thumbnail = try await loader.loadThumbnail(for: file)

        let loadCount = await contentLoader.loadCount
        XCTAssertNil(thumbnail)
        XCTAssertEqual(loadCount, 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeafThumbnailTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private actor ThumbnailContentLoader: FileContentLoading {
    func originalData(for file: ArchiveFile) async throws -> Data { Data() }

    private let content: LoadedFileContent
    private(set) var loadCount = 0

    init(content: LoadedFileContent) {
        self.content = content
    }

    func loadContent(for file: ArchiveFile) throws -> LoadedFileContent {
        loadCount += 1
        return content
    }
}
