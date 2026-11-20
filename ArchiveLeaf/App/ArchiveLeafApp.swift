import SwiftUI

@main
struct ArchiveLeafApp: App {
    private let environment = AppEnvironment.live()

    init() {
        VideoPlaybackFileStore().removeAll()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootView
        }
        .commands {
            ArchiveLeafCommands()
        }

        Settings {
            ArchiveLeafSettingsView(
                archiveResetter: environment.archiveResetter,
                incompleteImportPurger: environment.incompleteImportPurger,
                archiveBackupService: environment.archiveBackupService,
                archiveCache: environment.archiveCache,
                snapshotCache: environment.snapshotCache,
                bookmarkImporter: environment.bookmarkImporter
            )
        }
        #else
        WindowGroup {
            rootView
        }
        #endif
    }

    private var rootView: some View {
        RootView(
            viewModel: ArchiveViewModel(
                repository: environment.archiveRepository,
                importPreflight: environment.importPreflight,
                archiveImporter: environment.archiveImporter,
                archiveCache: environment.archiveCache,
                snapshotCache: environment.snapshotCache,
                connectivity: environment.connectivity
            ),
            archiveResetter: environment.archiveResetter,
            incompleteImportPurger: environment.incompleteImportPurger,
            archiveBackupService: environment.archiveBackupService,
            archiveCache: environment.archiveCache,
            snapshotCache: environment.snapshotCache,
            bookmarkImporter: environment.bookmarkImporter
        )
    }
}
