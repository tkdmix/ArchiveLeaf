import Foundation
import XCTest
@testable import ArchiveLeaf

final class ContentFileFormatDetectorTests: XCTestCase {
    private let detector = ContentFileFormatDetector()

    func testDetectsFormatsFromContentRegardlessOfExtension() async throws {
        let cases: [(String, FileDetectionResult)] = [
            ("{\"name\":\"ArchiveLeaf\"}", .viewable(format: .json, sourceEncoding: "utf-8")),
            ("name,size\nfirst,10\nsecond,20\n", .viewable(format: .plainText, sourceEncoding: "utf-8")),
            ("# ArchiveLeaf\n\nRead only.\n", .viewable(format: .markdown, sourceEncoding: "utf-8")),
            ("ordinary text\n", .viewable(format: .plainText, sourceEncoding: "utf-8"))
        ]

        for (content, expected) in cases {
            let url = try temporaryFile(data: Data(content.utf8), extension: "bin")
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await detector.detectFormat(for: url)
            XCTAssertEqual(result, expected)
        }
    }

    func testRecordsWindows31JOnlyWhenStrictShiftJISCannotDecode() async throws {
        let strictData = try XCTUnwrap("日本語のテキスト\n".data(using: .shiftJIS))
        let strictURL = try temporaryFile(data: strictData, extension: "bin")
        defer { try? FileManager.default.removeItem(at: strictURL) }
        let vendorData = Data([0x87, 0x40, 0x87, 0x41, 0x0A])
        let vendorURL = try temporaryFile(data: vendorData, extension: "bin")
        defer { try? FileManager.default.removeItem(at: vendorURL) }

        let strict = try await detector.detectFormat(for: strictURL)
        let vendor = try await detector.detectFormat(for: vendorURL)

        XCTAssertEqual(strict, .viewable(format: .plainText, sourceEncoding: "shift_jis"))
        XCTAssertEqual(vendor, .viewable(format: .plainText, sourceEncoding: "windows-31j"))
    }

    func testDetectsZIPSignatureAsInputArchive() async throws {
        let data = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        let url = try temporaryFile(data: data, extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await detector.detectFormat(for: url)
        XCTAssertEqual(result, .zipArchive)
    }

    func testDetectsMP4AndQuickTimeContainersBySignature() async throws {
        let mp4Signature = Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])
        let movSignature = Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20, 0x20])
        let mp4URL = try temporaryFile(data: mp4Signature, extension: "mp4")
        let movURL = try temporaryFile(data: movSignature, extension: "mov")
        defer {
            try? FileManager.default.removeItem(at: mp4URL)
            try? FileManager.default.removeItem(at: movURL)
        }

        let mp4 = try await detector.detectFormat(for: mp4URL)
        let mov = try await detector.detectFormat(for: movURL)

        XCTAssertEqual(mp4, .viewable(format: .mp4, sourceEncoding: nil))
        XCTAssertEqual(mov, .viewable(format: .mov, sourceEncoding: nil))
    }

    func testDoesNotTreatAnHEIFContainerAsVideo() async throws {
        let heifSignature = Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
        let url = try temporaryFile(data: heifSignature, extension: "heic")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await detector.detectFormat(for: url)
            XCTFail("Expected unsupported format")
        } catch ArchiveLeafError.unsupportedFormat {
        }
    }

    func testDetectsAPDFBySignatureAndOpensIt() async throws {
        let url = try temporaryFile(data: PDFTestDocument.data(), extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await detector.detectFormat(for: url)

        XCTAssertEqual(result, .viewable(format: .pdf, sourceEncoding: nil))
    }

    func testRefusesAPDFHeaderWithoutAReadableDocument() async throws {
        // What a truncated download looks like: the header survives, the pages do not.
        let url = try temporaryFile(data: Data("%PDF-1.7\nnot a document".utf8), extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await detector.detectFormat(for: url)
            XCTFail("Expected corrupted file")
        } catch ArchiveLeafError.corruptedFile {
        }
    }

    func testDetectsAPDFWhateverItsNameSays() async throws {
        let url = try temporaryFile(data: PDFTestDocument.data(), extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await detector.detectFormat(for: url)

        XCTAssertEqual(result, .viewable(format: .pdf, sourceEncoding: nil))
    }

    func testDetectsAStandardWeblocAsBookmark() async throws {
        let data = try BookmarkDocument.data(for: XCTUnwrap(URL(string: "https://example.com/path")))
        let url = try temporaryFile(data: data, extension: "webloc")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await detector.detectFormat(for: url)

        XCTAssertEqual(result, .viewable(format: .bookmark, sourceEncoding: nil))
    }

    func testRejectsWeblocWithoutAWebURL() async throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["URL": "file:///private/tmp/note.txt"],
            format: .xml,
            options: 0
        )
        let url = try temporaryFile(data: data, extension: "webloc")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await detector.detectFormat(for: url)
            XCTFail("Expected corrupted bookmark")
        } catch ArchiveLeafError.corruptedFile {
        }
    }

    func testDetectsDecodablePNGRegardlessOfExtension() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let url = try temporaryFile(data: png, extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await detector.detectFormat(for: url)
        XCTAssertEqual(result, .viewable(format: .png, sourceEncoding: nil))
    }

    func testRejectsUnsupportedBinary() async throws {
        let url = try temporaryFile(data: Data([0, 1, 2, 3, 4]), extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await detector.detectFormat(for: url)
            XCTFail("Expected unsupported format")
        } catch ArchiveLeafError.unsupportedFormat {
        }
    }

    func testReportsCorruptedSupportedImage() async throws {
        let url = try temporaryFile(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            extension: "png"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await detector.detectFormat(for: url)
            XCTFail("Expected corrupted file")
        } catch ArchiveLeafError.corruptedFile {
        }
    }

    private func temporaryFile(data: Data, extension pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
        try data.write(to: url)
        return url
    }
}
