import SwiftUI

struct FileMetadataView: View {
    let file: ArchiveFile
    /// Resolved by the caller: this view is handed a file, and a file carries only tag ids.
    var tagNames: [String] = []
    let loadedImage: LoadedImageContent?
    let onDisplayFormatChange: (ImportedFormat?) -> Void
    let onSourceEncodingChange: (ArchiveTextEncoding?) -> Void

    var body: some View {
        Form {
            // Only once renaming has moved the name away from it. Otherwise this repeats the name
            // already at the top of the window.
            if file.hasUserDefinedName {
                LabeledContent("Original Name", value: file.originalFileName)
            }
            if file.detectedFormat.isImage || file.detectedFormat.isVideo || file.detectedFormat.isPDF
                || file.detectedFormat == .bookmark {
                LabeledContent("Format", value: file.effectiveDisplayFormat.displayName)
            } else {
                Picker("View As", selection: displayFormatBinding) {
                    Text("Automatic (\(file.detectedFormat.displayName))")
                        .tag(nil as ImportedFormat?)
                    Divider()
                    ForEach(textDisplayFormats, id: \.self) { format in
                        Text(format.displayName).tag(format as ImportedFormat?)
                    }
                }
            }
            LabeledContent("Size", value: file.fileSize.formatted(.byteCount(style: .file)))
            if file.detectedFormat.isImage {
                if let sourceEncoding = file.sourceEncoding {
                    LabeledContent("Encoding", value: sourceEncoding)
                }
            } else if file.detectedFormat != .bookmark && !file.detectedFormat.isVideo && !file.detectedFormat.isPDF {
                Picker("Encoding", selection: sourceEncodingBinding) {
                    Text("Automatic (\(detectedEncodingName))")
                        .tag(nil as ArchiveTextEncoding?)
                    Divider()
                    ForEach(ArchiveTextEncoding.allCases, id: \.self) { encoding in
                        Text(encoding.displayName).tag(encoding as ArchiveTextEncoding?)
                    }
                }
            }
            if let dimensions {
                LabeledContent("Dimensions", value: dimensions)
            }
            LabeledContent("Imported", value: file.importedAt.formatted(date: .abbreviated, time: .shortened))
            if let sourceModifiedAt = file.sourceModifiedAt {
                LabeledContent("Source Modified", value: sourceModifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
            LabeledContent("Favorite", value: file.isFavorite ? "Yes" : "No")
            if !tagNames.isEmpty {
                LabeledContent("Tags", value: tagNames.formatted(.list(type: .and)))
            }
            if !file.contentHash.isEmpty {
                LabeledContent("SHA-256") {
                    Text(file.contentHash)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, idealWidth: 380)
        .padding()
    }

    private var dimensions: String? {
        let width = loadedImage?.pixelWidth ?? file.imagePixelWidth
        let height = loadedImage?.pixelHeight ?? file.imagePixelHeight
        guard let width, let height else { return nil }
        return "\(width) × \(height) px"
    }

    private let textDisplayFormats: [ImportedFormat] = [.plainText, .markdown, .json]

    private var displayFormatBinding: Binding<ImportedFormat?> {
        Binding(
            get: { file.displayFormatOverride },
            set: { onDisplayFormatChange($0) }
        )
    }

    private var detectedEncodingName: String {
        ArchiveTextEncoding.named(file.sourceEncoding)?.displayName
            ?? file.sourceEncoding
            ?? "Unknown"
    }

    private var sourceEncodingBinding: Binding<ArchiveTextEncoding?> {
        Binding(
            get: { file.sourceEncodingOverride },
            set: { onSourceEncodingChange($0) }
        )
    }
}
