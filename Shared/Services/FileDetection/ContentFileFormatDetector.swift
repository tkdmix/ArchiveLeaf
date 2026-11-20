import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ContentFileFormatDetector: FileFormatDetecting {
    func detectFormat(for url: URL) async throws -> FileDetectionResult {
        guard url.isFileURL else { throw ArchiveLeafError.unreadableFile }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ArchiveLeafError.unreadableFile
        }

        if isZIP(data) {
            return .zipArchive
        }
        if let videoFormat = detectVideo(in: data) {
            return .viewable(format: videoFormat, sourceEncoding: nil)
        }
        if hasSupportedImageSignature(data) {
            guard let imageFormat = detectImage(in: data) else {
                throw ArchiveLeafError.corruptedFile
            }
            return .viewable(format: imageFormat, sourceEncoding: nil)
        }
        if hasPDFSignature(data) {
            guard isReadablePDF(data) else {
                throw ArchiveLeafError.corruptedFile
            }
            return .viewable(format: .pdf, sourceEncoding: nil)
        }
        if url.pathExtension.lowercased() == "webloc" {
            do {
                _ = try BookmarkDocument.url(from: data)
                return .viewable(format: .bookmark, sourceEncoding: nil)
            } catch {
                throw ArchiveLeafError.corruptedFile
            }
        }
        guard let decoded = decodeText(data) else {
            throw ArchiveLeafError.unsupportedFormat
        }

        return .viewable(
            format: classifyText(decoded.text),
            sourceEncoding: decoded.encoding
        )
    }

    private func isZIP(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let signature = Array(data.prefix(4))
        return signature == [0x50, 0x4B, 0x03, 0x04]
            || signature == [0x50, 0x4B, 0x05, 0x06]
            || signature == [0x50, 0x4B, 0x07, 0x08]
    }

    /// MP4 and QuickTime both use the ISO base media container. The `ftyp` box is the stable
    /// content signature. Restricting its major brand matters because HEIF images also carry an
    /// `ftyp` box. Codec support is deliberately left to AVPlayer at viewing time.
    private func detectVideo(in data: Data) -> ImportedFormat? {
        guard data.count >= 12,
              data[4] == 0x66, data[5] == 0x74, data[6] == 0x79, data[7] == 0x70 else {
            return nil
        }
        let brand = String(decoding: data[8..<12], as: UTF8.self)
        if brand == "qt  " { return .mov }
        let mp4Brands: Set<String> = ["isom", "iso2", "mp41", "mp42", "M4V ", "M4VH", "M4VP"]
        return mp4Brands.contains(brand) ? .mp4 : nil
    }

    /// `%PDF-` is the header every PDF starts with. The signature alone is not enough — a
    /// truncated download keeps it — so the document is also opened, the same way an image is
    /// decoded rather than trusted to its magic bytes.
    private func hasPDFSignature(_ data: Data) -> Bool {
        Array(data.prefix(5)) == [0x25, 0x50, 0x44, 0x46, 0x2D]
    }

    private func isReadablePDF(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return false
        }
        // An encrypted PDF opens but shows nothing without its password, and ArchiveLeaf has
        // nowhere to ask for one. Refused at the door rather than filed as a blank document.
        return document.numberOfPages > 0 && !document.isEncrypted
    }

    private func detectImage(in data: Data) -> ImportedFormat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let typeIdentifier = CGImageSourceGetType(source) as String? else {
            return nil
        }

        if UTType(typeIdentifier)?.conforms(to: .jpeg) == true { return .jpeg }
        if UTType(typeIdentifier)?.conforms(to: .png) == true { return .png }
        return nil
    }

    private func hasSupportedImageSignature(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(8))
        let isJPEG = bytes.starts(with: [0xFF, 0xD8, 0xFF])
        let isPNG = bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return isJPEG || isPNG
    }

    private func decodeText(_ data: Data) -> (text: String, encoding: String)? {
        let bomEncodings: [([UInt8], ArchiveTextEncoding)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BE),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LE),
            ([0xFE, 0xFF], .utf16BE),
            ([0xFF, 0xFE], .utf16LE),
            ([0xEF, 0xBB, 0xBF], .utf8)
        ]
        for (bom, encoding) in bomEncodings where data.starts(with: bom) {
            guard let text = encoding.decode(data), isPlausibleText(text) else {
                return nil
            }
            return (text, encoding.rawValue)
        }

        guard !data.contains(0) else { return nil }

        for encoding in ArchiveTextEncoding.detectionOrder {
            if let text = encoding.decode(data), isPlausibleText(text) {
                return (text, encoding.rawValue)
            }
        }
        return nil
    }

    private func isPlausibleText(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            scalar.value == 0 || (scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t")
        }
    }

    private func classifyText(_ text: String) -> ImportedFormat {
        let data = Data(text.utf8)
        if (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil {
            return .json
        }
        if isMarkdown(text) { return .markdown }
        return .plainText
    }

    private func isMarkdown(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("# ")
                || trimmed.hasPrefix("## ")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || (trimmed.hasPrefix("[") && trimmed.contains("]("))
                || trimmed.hasPrefix("```")
        }
    }
}
