import Foundation

struct ImportPolicy: Sendable {
    let maximumFolderDepth: Int
    let maximumRelativePathLength: Int
    let maximumTextImportSize: Int64
    let maximumTextDisplaySize: Int64
    let maximumRichTextDisplaySize: Int64
    let maximumImageSize: Int64
    let maximumVideoSize: Int64
    let maximumPDFSize: Int64
    let maximumBatchFileCount: Int
    let maximumBatchSize: Int64

    init(
        maximumFolderDepth: Int = 32,
        maximumRelativePathLength: Int = 1_024,
        maximumTextImportSize: Int64 = 10 * 1_024 * 1_024,
        maximumTextDisplaySize: Int64 = 10 * 1_024 * 1_024,
        maximumRichTextDisplaySize: Int64 = 2 * 1_024 * 1_024,
        maximumImageSize: Int64 = 50 * 1_024 * 1_024,
        maximumVideoSize: Int64 = 200 * 1_024 * 1_024,
        maximumPDFSize: Int64 = 50 * 1_024 * 1_024,
        maximumBatchFileCount: Int = 1_000,
        maximumBatchSize: Int64 = 500 * 1_024 * 1_024
    ) {
        self.maximumFolderDepth = maximumFolderDepth
        self.maximumRelativePathLength = maximumRelativePathLength
        self.maximumTextImportSize = maximumTextImportSize
        self.maximumTextDisplaySize = maximumTextDisplaySize
        self.maximumRichTextDisplaySize = maximumRichTextDisplaySize
        self.maximumImageSize = maximumImageSize
        self.maximumVideoSize = maximumVideoSize
        self.maximumPDFSize = maximumPDFSize
        self.maximumBatchFileCount = maximumBatchFileCount
        self.maximumBatchSize = maximumBatchSize
    }

    /// The most generous of the per-format limits, so a file can be refused for size before anything
    /// reads it. Which limit applies depends on what the file turns out to be, and finding that out
    /// means opening it — a text file is decoded whole, and every candidate encoding tried, before
    /// it is classified. Nothing larger than this can be accepted whatever it is.
    var maximumAcceptableFileSize: Int64 {
        max(maximumImageSize, max(maximumVideoSize, max(maximumPDFSize, maximumTextImportSize)))
    }
}
