import SwiftUI

#if !os(macOS)
/// The settings sheet used by both the compact tab layout and the regular split layout.
///
/// macOS uses the standard Settings scene instead, so this stays iOS and iPadOS only.
struct ArchiveSettingsSheet: View {
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: (any ArchiveCaching)?
    let snapshotCache: (any ArchiveSnapshotCaching)?
    let bookmarkImporter: (any BookmarkImporting)?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ArchiveLeafSettingsView(
                archiveResetter: archiveResetter,
                incompleteImportPurger: incompleteImportPurger,
                archiveBackupService: archiveBackupService,
                archiveCache: archiveCache,
                snapshotCache: snapshotCache,
                bookmarkImporter: bookmarkImporter
            )
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
#endif
