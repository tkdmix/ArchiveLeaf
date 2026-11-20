import Foundation

enum ImportedFormat: String, CaseIterable, Codable, Sendable {
    case plainText
    case markdown
    case json
    case csv
    case jpeg
    case png
    case bookmark
    case mp4
    case mov
    case pdf

    var displayName: String {
        String(localized: displayNameResource)
    }

    private var displayNameResource: LocalizedStringResource {
        switch self {
        case .plainText: "Plain Text"
        case .markdown: "Markdown"
        case .json: "JSON"
        case .csv: "CSV"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .bookmark: "Bookmark"
        case .mp4: "MPEG-4 Video"
        case .mov: "QuickTime Movie"
        case .pdf: "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .jpeg, .png: "photo"
        case .markdown, .plainText: "doc.text"
        case .json, .csv: "tablecells"
        case .bookmark: "bookmark"
        case .mp4, .mov: "film"
        case .pdf: "doc.richtext"
        }
    }

    var isImage: Bool {
        self == .jpeg || self == .png
    }

    var isVideo: Bool {
        self == .mp4 || self == .mov
    }

    /// A page description, not text and not a picture. Presented by PDFKit, which brings its own
    /// scrolling, magnification, and search.
    var isPDF: Bool { self == .pdf }

    /// Search belongs to the chosen presentation, not to whether bytes have happened to finish
    /// loading. Legacy CSV records are presented as plain text and remain searchable.
    var supportsDocumentSearch: Bool { !isImage && !isVideo && !isPDF && self != .bookmark }
}
