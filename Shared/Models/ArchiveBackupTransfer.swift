import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A new identifier, because the tag specification of an old one cannot be changed in practice.
    ///
    /// `…ArchiveLeaf.backup` was declared with the `archiveleafbackup` extension, and every copy of
    /// the app ever built still declares it that way — archived Dogfood builds and DerivedData
    /// products included. LaunchServices answers from whichever registration it already holds, so a
    /// rebuilt app announcing a new extension under the same identifier was ignored: the save panel
    /// still offered the old extension, and an export written as `.albak` could not be produced at
    /// all, since the file no longer matched the type it was being exported as. An identifier that
    /// has never been registered has nothing to lose the argument to.
    static let archiveLeafBackup = UTType(
        exportedAs: "io.github.inadaman.ArchiveLeaf.albak",
        conformingTo: .package
    )
}

struct ArchiveBackupTransfer: Transferable, Sendable {
    let packageURL: URL

    /// The suggested name is required, not cosmetic: without it the export builds an
    /// `NSFileWrapper` with an empty `preferredFilename`, which raises. The exporter's
    /// `defaultFilename` still decides what the user actually sees in the save panel.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .archiveLeafBackup) { backup in
            SentTransferredFile(backup.packageURL, allowAccessingOriginalFile: true)
        }
        .suggestedFileName("ArchiveLeaf-Backup.\(ArchiveBackupPackage.pathExtension)")
    }
}
