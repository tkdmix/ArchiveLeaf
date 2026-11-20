import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The picture of a file, or the symbol standing in for one. Its own view so that a row keeps the
/// same image while its name is being edited.
struct ArchiveFileThumbnail: View {
    let file: ArchiveFile
    let viewModel: ArchiveViewModel
    @State private var thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData, let image = platformImage(from: thumbnailData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: file.effectiveDisplayFormat.systemImage)
                    .frame(width: 28, height: 28)
            }
        }
        .accessibilityHidden(true)
        .task(id: fileThumbnailKey) {
            thumbnailData = try? await viewModel.loadThumbnail(for: file)
        }
    }

    private var fileThumbnailKey: String {
        "\(file.id.uuidString)-\(file.contentHash)-\(file.effectiveDisplayFormat.rawValue)"
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

#if os(macOS)
/// Room enough beside a picture. A label's own spacing is set for a glyph, which is narrower than
/// a thumbnail and reads as part of the same shape as the name when it sits this close.
let archiveFileLabelSpacing: CGFloat = 8
#endif
