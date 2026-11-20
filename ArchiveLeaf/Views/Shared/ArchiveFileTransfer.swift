import CoreTransferable
import Foundation

/// A file offered to a share sheet, written out only if the user actually shares it.
///
/// A list row cannot hand `ShareLink` a URL: that would mean fetching and writing every file on
/// screen on the chance one gets shared. Exporting through `Transferable` defers the work to the
/// moment it is needed.
struct ArchiveFileTransfer: Transferable, Sendable {
    let file: ArchiveFile
    let exporter: ArchiveFileExporter

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { transfer in
            guard let url = await transfer.exporter.fileURL(for: transfer.file) else {
                throw ArchiveLeafError.unreadableFile
            }
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }

    }
}
