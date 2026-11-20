import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ArchiveLeaf

final class RepositoryFileContentLoaderTests: XCTestCase {
    func testLoadsPlainTextUsingRecordedEncoding() async throws {
        let text = "ArchiveLeaf 日本語"
        let data = try XCTUnwrap(text.data(using: .shiftJIS))
        let file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            sourceEncoding: "shift_jis",
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .plainText(text))
    }

    func testEncodingOverrideReplacesTheRecordedEncoding() async throws {
        let text = "ArchiveLeaf 日本語"
        let data = try XCTUnwrap(text.data(using: .japaneseEUC))
        var file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            sourceEncoding: "shift_jis",
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected the recorded encoding to fail on EUC-JP bytes")
        } catch {
            XCTAssertEqual(error as? ArchiveLeafError, .unreadableFile)
        }
        file.sourceEncodingOverride = .eucJP
        let corrected = try await loader.loadContent(for: file)

        XCTAssertEqual(corrected, .plainText(text))
    }

    func testWindows31JOverrideDecodesVendorExtensionsStrictShiftJISRejects() async throws {
        let circledNumbers = Data([0x87, 0x40, 0x87, 0x41, 0x87, 0x42])
        var file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            sourceEncoding: "shift_jis",
            fileSize: Int64(circledNumbers.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: circledNumbers)

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected strict Shift_JIS to reject NEC vendor extensions")
        } catch {
            XCTAssertEqual(error as? ArchiveLeafError, .unreadableFile)
        }
        file.sourceEncodingOverride = .windows31J
        let corrected = try await loader.loadContent(for: file)

        XCTAssertEqual(corrected, .plainText("①②③"))
    }

    func testShiftJISAndWindows31JDisagreeOnSharedCodePoints() async throws {
        let waveDash = Data([0x81, 0x60])
        var file = ArchiveFile(
            originalFileName: "note.txt",
            detectedFormat: .plainText,
            sourceEncoding: "shift_jis",
            fileSize: Int64(waveDash.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: waveDash)

        let strict = try await loader.loadContent(for: file)
        file.sourceEncodingOverride = .windows31J
        let vendor = try await loader.loadContent(for: file)

        XCTAssertEqual(strict, .plainText("\u{301C}"))
        XCTAssertEqual(vendor, .plainText("\u{FF5E}"))
    }

    func testPrettyPrintsSmallJSONWithoutChangingItsValue() async throws {
        let data = Data("{\"z\":1,\"a\":2}".utf8)
        let file = ArchiveFile(
            originalFileName: "data.json",
            detectedFormat: .json,
            sourceEncoding: "utf-8",
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        let content = try await loader.loadContent(for: file)

        guard case .json(let text) = content else { return XCTFail("Expected JSON") }
        XCTAssertTrue(text.contains("\n"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Int]
        )
        XCTAssertEqual(object, ["z": 1, "a": 2])
    }

    func testLoadsLegacyCSVRecordAsPlainText() async throws {
        let data = Data("name,note\nLeaf,\"one, two\"\nTree,\"line 1\nline 2\"\n".utf8)
        let file = ArchiveFile(
            originalFileName: "data.csv",
            detectedFormat: .csv,
            sourceEncoding: "utf-8",
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .plainText(String(decoding: data, as: UTF8.self)))
    }

    func testLoadsBookmarkWithoutFetchingThePage() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference?q=leaf"))
        let data = try BookmarkDocument.data(for: url)
        let file = ArchiveFile(
            originalFileName: "Reference.webloc",
            detectedFormat: .bookmark,
            fileSize: Int64(data.count),
            contentHash: "bookmark-hash"
        )
        let loader = loader(file: file, data: data)

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .bookmark(url))
    }

    func testUsesLightweightSourceViewForLargeJSON() async throws {
        let data = Data("{\"prompt\":\"Keep the original source\"}".utf8)
        let file = ArchiveFile(
            originalFileName: "prompt.json",
            detectedFormat: .json,
            sourceEncoding: "utf-8",
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(
                files: [file],
                assetDataByFileID: [file.id: data]
            ),
            maximumRichTextDisplaySize: 10
        )

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .plainText(String(decoding: data, as: UTF8.self)))
    }

    func testRejectsTextAboveDisplayLimitBeforeReadingAsset() async {
        let file = ArchiveFile(
            originalFileName: "large.txt",
            detectedFormat: .plainText,
            fileSize: 11,
            contentHash: "hash"
        )
        let loader = RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(files: [file]),
            maximumTextDisplaySize: 10
        )

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected display limit error")
        } catch {
            guard case FileContentLoadingError.displaySizeExceeded(10) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLoadsValidatedPNGData() async throws {
        let data = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let file = ArchiveFile(
            originalFileName: "pixel.png",
            detectedFormat: .png,
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .image(LoadedImageContent(
            data: data,
            pixelWidth: 1,
            pixelHeight: 1
        )))
    }

    /// A photograph taken upright stores landscape pixels and a quarter turn beside them. The
    /// viewer sizes its frame from these numbers, so reporting the stored pair would show the
    /// picture flattened into the wrong shape.
    func testReportsImageSizeAsTheOrientationTagShowsIt() async throws {
        let data = try jpegData(width: 4, height: 2, orientation: 6)
        let file = ArchiveFile(
            originalFileName: "upright.jpg",
            detectedFormat: .jpeg,
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        guard case .image(let image) = try await loader.loadContent(for: file) else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 4)
    }

    func testReportsImageSizeUnchangedWithoutAQuarterTurn() async throws {
        let data = try jpegData(width: 4, height: 2, orientation: 1)
        let file = ArchiveFile(
            originalFileName: "flat.jpg",
            detectedFormat: .jpeg,
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        guard case .image(let image) = try await loader.loadContent(for: file) else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(image.pixelWidth, 4)
        XCTAssertEqual(image.pixelHeight, 2)
    }

    private func jpegData(width: Int, height: Int, orientation: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testRejectsCorruptedImageData() async {
        let data = Data("not an image".utf8)
        let file = ArchiveFile(
            originalFileName: "broken.jpg",
            detectedFormat: .jpeg,
            fileSize: Int64(data.count),
            contentHash: "hash"
        )
        let loader = loader(file: file, data: data)

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected corrupted image error")
        } catch {
            XCTAssertEqual(error as? ArchiveLeafError, .corruptedFile)
        }
    }

    func testLoadsVideoAsAFileURLWithoutDecodingItsBytes() async throws {
        let data = Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])
        let file = ArchiveFile(
            originalFileName: "clip.mp4",
            detectedFormat: .mp4,
            fileSize: Int64(data.count),
            contentHash: "video-hash"
        )
        let loader = loader(file: file, data: data)

        guard case .video(let video) = try await loader.loadContent(for: file) else {
            return XCTFail("Expected video URL")
        }
        defer { try? FileManager.default.removeItem(at: video.url) }
        XCTAssertEqual(video.url.pathExtension.lowercased(), "mp4")
        XCTAssertEqual(try Data(contentsOf: video.url), data)
    }

    func testEnforcesVideoDisplayLimitIndependently() async throws {
        let data = Data(repeating: 0, count: 12)
        let file = ArchiveFile(
            originalFileName: "clip.mov",
            detectedFormat: .mov,
            fileSize: Int64(data.count),
            contentHash: "video-hash"
        )
        let loader = RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(
                files: [file],
                assetDataByFileID: [file.id: data]
            ),
            maximumVideoDisplaySize: 11
        )

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected display limit error")
        } catch {
            guard case FileContentLoadingError.displaySizeExceeded(11) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLoadsPDFAsItsImportedBytes() async throws {
        let data = PDFTestDocument.data()
        let file = ArchiveFile(
            originalFileName: "paper.pdf",
            detectedFormat: .pdf,
            fileSize: Int64(data.count),
            contentHash: "pdf-hash"
        )
        let loader = loader(file: file, data: data)

        guard case .pdf(let loaded) = try await loader.loadContent(for: file) else {
            return XCTFail("Expected PDF content")
        }
        XCTAssertEqual(loaded, data)
    }

    func testEnforcesPDFDisplayLimitIndependently() async throws {
        let data = PDFTestDocument.data()
        let file = ArchiveFile(
            originalFileName: "paper.pdf",
            detectedFormat: .pdf,
            fileSize: Int64(data.count),
            contentHash: "pdf-hash"
        )
        let loader = RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(
                files: [file],
                assetDataByFileID: [file.id: data]
            ),
            maximumPDFDisplaySize: Int64(data.count - 1)
        )

        do {
            _ = try await loader.loadContent(for: file)
            XCTFail("Expected display limit error")
        } catch {
            guard case FileContentLoadingError.displaySizeExceeded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testVideoPlaybackStoreRemovesFilesLeftByAnEarlierRun() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveLeaf-VideoPlayback-Test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.deletingLastPathComponent()
            .appendingPathComponent("ArchiveLeaf-Video-Source-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let data = Data([0, 1, 2, 3])
        try data.write(to: sourceURL)
        let file = ArchiveFile(
            originalFileName: "clip.mov",
            detectedFormat: .mov,
            fileSize: Int64(data.count),
            contentHash: "video-hash"
        )
        let store = VideoPlaybackFileStore(directoryURL: directory)

        let copyURL = try store.copy(of: sourceURL, for: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))

        store.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testLoadsFromCacheWhenRepositoryAssetIsUnavailable() async throws {
        let data = Data("cached text".utf8)
        let file = ArchiveFile(
            originalFileName: "cached.txt",
            detectedFormat: .plainText,
            sourceEncoding: "utf-8",
            fileSize: Int64(data.count),
            contentHash: "cached-hash"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskArchiveCache(
            directoryURL: directory,
            policy: CachePolicy(maximumSize: 100)
        )
        try await cache.store(data, for: file.contentHash)
        let loader = RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(files: [file]),
            cache: cache
        )

        let content = try await loader.loadContent(for: file)

        XCTAssertEqual(content, .plainText("cached text"))
    }

    private func loader(file: ArchiveFile, data: Data) -> RepositoryFileContentLoader {
        RepositoryFileContentLoader(
            repository: InMemoryArchiveRepository(
                files: [file],
                assetDataByFileID: [file.id: data]
            )
        )
    }
}
