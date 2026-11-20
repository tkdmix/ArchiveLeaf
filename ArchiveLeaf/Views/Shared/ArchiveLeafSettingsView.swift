import SwiftUI

/// The label colour of a settings action, brought together across platforms. The frame is not.
///
/// iOS draws a Form button as blue text, red when it destroys something. macOS draws a bordered
/// control with a black label, and `role: .destructive` does not colour it — so on the Mac, `Delete
/// My Archive…` looked exactly like `Export Backup…`. That is the one place the difference carries
/// meaning rather than style, which is why only the colour is unified and the platform keeps its
/// own control: this is not macOS wearing an iOS appearance.
private struct SettingsActionLabel: ViewModifier {
    let isDestructive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        #if os(macOS)
        if isEnabled {
            content
                .buttonStyle(.link)
                .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
        } else {
            // An explicit foreground style would override the standard disabled appearance.
            content.buttonStyle(.link)
        }
        #else
        content
        #endif
    }
}

private extension View {
    func settingsActionLabel(destructive: Bool = false) -> some View {
        modifier(SettingsActionLabel(isDestructive: destructive))
    }
}

/// What a settings action has to say when it finishes, whichever action it was.
///
/// One of these rather than five separate messages, because every outcome in this screen has the
/// same shape — a title, a sentence, and OK — and five alerts have nowhere to go that works.
/// Stacked on one view, only the outermost answers. Moved onto each `Section`, none answered on
/// iPad: an alert on a `Section` did not reach the screen there, though a `fileImporter` on one did
/// on Mac and iPhone, so this is an observation and not a rule about what a `Section` is. Both
/// arrangements were tried on the devices, and both swallowed the report of an archive deletion
/// that had already failed — which is how the failure stayed invisible for two rounds.
///
/// One alert, on the form itself, is the arrangement with nothing left to be uncertain about.
private struct SettingsOutcome: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String.LocalizationValue, message: String) {
        self.title = String(localized: title)
        self.message = message
    }
}

struct ArchiveLeafSettingsView: View {
    let archiveResetter: (any ArchiveResetting)?
    let incompleteImportPurger: (any IncompleteImportPurging)?
    let archiveBackupService: (any ArchiveBackupPackageServicing)?
    let archiveCache: (any ArchiveCaching)?
    let snapshotCache: (any ArchiveSnapshotCaching)?
    let bookmarkImporter: (any BookmarkImporting)?
    @State private var outcome: SettingsOutcome?
    @State private var isConfirmingReset = false
    @State private var isConfirmingFinalReset = false
    @State private var isResetting = false
    @State private var isCountingIncompleteImports = false
    @State private var isPurgingIncompleteImports = false
    @State private var incompleteImportCount = 0
    @State private var isConfirmingIncompletePurge = false
    @State private var cacheSize: Int64?
    @State private var isConfirmingCacheClear = false
    @State private var isClearingCache = false
    @State private var isPreparingBackup = false
    @State private var isExportingBackup = false
    @State private var preparedBackup: ArchiveBackupTransfer?
    @State private var isChoosingRestore = false
    @State private var isInspectingRestore = false
    @State private var isRestoring = false
    @State private var pendingRestore: PendingRestore?
    @State private var isShelfLocked: Bool
    @State private var bookmarkImportSource: BookmarkImportSource = .raindrop
    @State private var isChoosingBookmarkExport = false
    @State private var isImportingBookmarks = false
    private let shelfLockSettings = ShelfLockSettingsStore()
    private let shelfUnlocker: any ShelfUnlocking = LocalAuthenticationUnlocker()

    init(
        archiveResetter: (any ArchiveResetting)? = nil,
        incompleteImportPurger: (any IncompleteImportPurging)? = nil,
        archiveBackupService: (any ArchiveBackupPackageServicing)? = nil,
        archiveCache: (any ArchiveCaching)? = nil,
        snapshotCache: (any ArchiveSnapshotCaching)? = nil,
        bookmarkImporter: (any BookmarkImporting)? = nil
    ) {
        self.archiveResetter = archiveResetter
        self.incompleteImportPurger = incompleteImportPurger
        self.archiveBackupService = archiveBackupService
        self.archiveCache = archiveCache
        self.snapshotCache = snapshotCache
        self.bookmarkImporter = bookmarkImporter
        _isShelfLocked = State(initialValue: ShelfLockSettingsStore().isEnabled)
    }

    /// The sections themselves, held apart from the alerts and dialogs that follow them in `body`.
    /// Together they are more than the compiler will type-check as one expression.
    ///
    /// The order is the one the `Settings layout` section of docs/DESIGN.md states: sections
    /// descend by what a mistaken press costs, from facts that lose nothing to deletions that
    /// cannot be undone.
    private var settingsForm: some View {
        Form {
            Section("Archive") {
                LabeledContent("File contents") { Text("Read-only") }
                LabeledContent("Cloud storage") { Text("Private Database") }
            }

            privacySection

            bookmarkImportSection

            backupSection

            localCacheSection

            deleteSection
        }
        .onChange(of: isShelfLocked) { _, isLocked in
            shelfLockSettings.setEnabled(isLocked)
        }
        // The one alert in this screen, and it is on the form itself: a real view, with nothing to
        // compete with. Confirmations stay on their own buttons, where an iPad popover has
        // something to point at; those are a different presentation and do not contend with this.
        .alert(
            outcome?.title ?? "",
            isPresented: Binding(
                get: { outcome != nil },
                set: { if !$0 { outcome = nil } }
            ),
            presenting: outcome
        ) { _ in
            Button("OK") { outcome = nil }
        } message: { outcome in
            Text(outcome.message)
        }
    }

    /// Nothing is presented from here.
    ///
    /// Every confirmation, alert, and picker belongs to the control that raises it, for two reasons
    /// found on a device rather than in a test. A view presents one picker and answers one dialog of
    /// a kind; nine of them stacked here meant whichever sat outermost replied and the rest were
    /// silently dropped — restore never opened, and a failed archive deletion reported nothing at
    /// all. And on iPad a confirmation is a popover, which points at the view it is attached to: on
    /// this whole scrolling form it had nowhere to point and collapsed against the top of the sheet.
    /// Attached to its own button, it has both a place to come from and no one to compete with.
    var body: some View {
        settingsForm
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 480, height: 480)
        .padding()
        #endif
        .task { await refreshCacheSize() }
    }

    private var resetScopeDescription: String {
        #if DEBUG
        String(localized: "Permanently deletes all ArchiveLeaf records and assets from the Development private database.")
        #else
        String(localized: "Permanently deletes all of your ArchiveLeaf records and assets from iCloud Private Database.")
        #endif
    }

    /// Bookmarks from another app, kept apart from what the shelf already holds.
    ///
    /// One button per app rather than one button that reads any file: both exports are plain text,
    /// and guessing which app wrote one would be guessing at the name its folder and its tags are
    /// about to be given. The reader knows which app they exported from.
    private var bookmarkImportSection: some View {
        Section("Import Bookmarks") {
            ForEach(BookmarkImportSource.allCases) { source in
                Button("Import from \(source.name)…") {
                    bookmarkImportSource = source
                    isChoosingBookmarkExport = true
                }
                .settingsActionLabel()
                .disabled(bookmarkImporter == nil || isImportingBookmarks || isResetting)
            }

            if isImportingBookmarks {
                ProgressView("Importing bookmarks…")
            }

            Text("Each app's bookmarks go into a folder of its own name, and its tags arrive beneath a tag of that name. Bookmarks already on your shelf are skipped, and notes, excerpts, and cover images are not imported.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $isChoosingBookmarkExport,
            allowedContentTypes: [bookmarkImportSource.contentType]
        ) { result in
            importBookmarks(result)
        }
    }

    /// The archive going out and coming back, carrying its own file importer.
    ///
    /// The importer belongs to this section rather than to `body` because SwiftUI presents one
    /// `fileImporter` per view. Two attached to the same view do not take turns: the outer one
    /// answers and the inner one never opens. Restore stopped opening on every platform at once the
    /// moment the bookmark importer was added beside it, and nothing said so — the button simply
    /// did nothing. One picker per view, owned by the section that opens it.
    private var backupSection: some View {
        Section("Backup") {
            Button("Export Backup…") {
                prepareBackup()
            }
            .settingsActionLabel()
            .disabled(archiveBackupService == nil || isPreparingBackup || isResetting)
            .fileExporter(
                isPresented: $isExportingBackup,
                item: preparedBackup,
                contentTypes: [.archiveLeafBackup],
                defaultFilename: defaultBackupName
            ) { result in
                finishBackupExport(result)
            }

            if isPreparingBackup {
                ProgressView("Preparing backup…")
            }

            Text("Exports completed items outside Trash. Restore will require an empty Archive.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Restore from Backup…") {
                isChoosingRestore = true
            }
            .settingsActionLabel()
            .disabled(archiveBackupService == nil || isInspectingRestore || isRestoring || isResetting)
            .confirmationDialog(
                "Restore This Backup?",
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { finishPendingRestore() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Restore") { performRestore() }
                Button("Cancel", role: .cancel) { finishPendingRestore() }
            } message: {
                Text(pendingRestore?.summary ?? "")
            }

            #if os(iOS)
            Text("In Files, choose a backup from On My iPhone or On My iPad. If it is stored elsewhere, copy it onto this device first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif

            if isInspectingRestore {
                ProgressView("Reading backup…")
            }
            if isRestoring {
                ProgressView("Restoring…")
            }

            Text("Writes a backup back into an empty Archive. It does not merge with, or replace, items you already have.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $isChoosingRestore,
            allowedContentTypes: [.archiveLeafBackup]
        ) { result in
            inspectRestore(result)
        }
    }

    /// What is on this device and can be thrown away, held apart from what deleting really means.
    private var localCacheSection: some View {
        Section("Local Cache") {
            LabeledContent(
                "Usage",
                value: cacheSize?.formatted(.byteCount(style: .file))
                    ?? String(localized: "Calculating…")
            )
            Button("Clear Cache…", role: .destructive) {
                isConfirmingCacheClear = true
            }
            .settingsActionLabel(destructive: true)
            .disabled(archiveCache == nil || isClearingCache || cacheSize == 0)
            .confirmationDialog(
                "Clear Local Cache?",
                isPresented: $isConfirmingCacheClear,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) { clearCache() }
            } message: {
                Text("Files can be downloaded from iCloud again when needed.")
            }

            Text("Cached files are disposable. Clearing them does not delete anything from iCloud.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The last section, because nothing it does can be taken back.
    ///
    /// Named for what both of its buttons do rather than for what they act on: `Data` named the
    /// subject and warned nobody. Clearing the local cache is worded destructively too, and stays
    /// in its own section above — putting an everyday button beside this one places a mis-tap where
    /// it costs the most.
    private var deleteSection: some View {
        Section("Delete") {
            if archiveResetter == nil && incompleteImportPurger == nil {
                Text("No CloudKit archive is connected.")
                    .foregroundStyle(.secondary)
            }

            if incompleteImportPurger != nil {
                Button("Remove Incomplete Imports…", role: .destructive) {
                    countIncompleteImports()
                }
                .settingsActionLabel(destructive: true)
                .disabled(isCountingIncompleteImports || isPurgingIncompleteImports || isResetting)
                .confirmationDialog(
                    "Remove \(incompleteImportCount) Incomplete Imports?",
                    isPresented: $isConfirmingIncompletePurge,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) { removeIncompleteImports() }
                } message: {
                    Text("These records never finished importing and cannot be recovered. Completed files and folders are not affected.")
                }

                Text("Interrupted or failed imports can leave hidden records in iCloud. Removing them never touches completed files or folders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if archiveResetter != nil {
                Button("Delete My Archive…", role: .destructive) {
                    isConfirmingReset = true
                }
                .settingsActionLabel(destructive: true)
                .disabled(isResetting)
                // Two plain confirmations, and no typed word. Asking for one meant an alert with a
                // TextField, which on iOS 17 takes the tap and runs nothing — the archive could not
                // be deleted at all on the floor device, and the safeguard was what stopped it. A
                // second confirmation costs one more press and cannot fail that way.
                .confirmationDialog(
                    "Delete Your Entire Archive?",
                    isPresented: $isConfirmingReset,
                    titleVisibility: .visible
                ) {
                    Button("Continue…", role: .destructive) {
                        isConfirmingFinalReset = true
                    }
                } message: {
                    Text("This permanently deletes every ArchiveLeaf folder, file, and stored asset from iCloud. This cannot be undone on any device.")
                }
                .alert("Delete My Archive?", isPresented: $isConfirmingFinalReset) {
                    Button("Delete My Archive", role: .destructive) {
                        resetArchive()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This is the last step. Nothing here can be recovered, on this device or any other.")
                }

                if isResetting {
                    ProgressView("Deleting your archive…")
                }

                Text(resetScopeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle("Lock Shelf", isOn: $isShelfLocked)
                .disabled(lockAvailability == .unavailable)

            Text(lockDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Link("Privacy Policy", destination: URL(string: "https://tkdmix.com/apps/archiveleaf/support/#privacy")!)
                .accessibilityIdentifier("privacyPolicyLink")
        }
    }

    private var lockAvailability: ShelfLockAvailability {
        shelfUnlocker.availability
    }

    /// What the reader will be asked for, named before they have ever seen the sheet — and, where
    /// the switch is greyed out, why. A disabled row with no reason beside it is indistinguishable
    /// from a broken one.
    private var lockDescription: String {
        switch lockAvailability {
        case .biometry(.faceID):
            String(localized: "Opens with Face ID, or your device passcode.")
        case .biometry(.touchID):
            #if os(macOS)
            String(localized: "Opens with Touch ID, or your login password.")
            #else
            String(localized: "Opens with Touch ID, or your device passcode.")
            #endif
        case .passcodeOnly:
            #if os(macOS)
            String(localized: "Opens with your login password.")
            #else
            String(localized: "Opens with your device passcode.")
            #endif
        case .unavailable:
            #if os(macOS)
            String(localized: "This Mac has no login password set. Set one in System Settings to lock your shelf.")
            #else
            String(localized: "This device has no passcode set. Set one in Settings to lock your shelf.")
            #endif
        }
    }

    private func resetArchive() {
        guard let archiveResetter else { return }
        isResetting = true
        Task {
            do {
                let result = try await archiveResetter.resetArchive()
                try? await archiveCache?.removeAll()
                try? await snapshotCache?.removeSnapshot()
                await refreshCacheSize()
                // Folders and files, not their sum. The result has carried both counts all along,
                // and a restore says "9 folders and 26 files" — reporting the same archive as "35
                // items" on the way out described a different thing on each side of the round trip.
                outcome = SettingsOutcome(title: "Archive Deletion", message: String(
                    localized: "Deleted \(result.deletedFolderCount) folders and \(result.deletedFileCount) files."
                ))
                NotificationCenter.default.post(
                    name: .archiveLeafArchiveDidReplace,
                    object: ArchiveSnapshot(folders: [], files: [])
                )
            } catch {
                outcome = SettingsOutcome(title: "Archive Deletion", message: String(localized: "Reset stopped: \(error.localizedDescription)"))
            }
            isResetting = false
        }
    }

    private func countIncompleteImports() {
        guard let incompleteImportPurger else { return }
        isCountingIncompleteImports = true
        Task {
            do {
                let count = try await incompleteImportPurger.fetchIncompleteImportCount()
                if count == 0 {
                    outcome = SettingsOutcome(title: "Incomplete Imports", message: String(localized: "No incomplete imports were found."))
                } else {
                    incompleteImportCount = count
                    isConfirmingIncompletePurge = true
                }
            } catch {
                outcome = SettingsOutcome(title: "Incomplete Imports", message: String(localized: "Could not read incomplete imports: \(error.localizedDescription)"))
            }
            isCountingIncompleteImports = false
        }
    }

    private func removeIncompleteImports() {
        guard let incompleteImportPurger else { return }
        isPurgingIncompleteImports = true
        Task {
            do {
                let result = try await incompleteImportPurger.removeIncompleteImports()
                outcome = SettingsOutcome(title: "Incomplete Imports", message: String(localized: "Removed \(result.deletedFileCount) incomplete imports."))
            } catch {
                outcome = SettingsOutcome(title: "Incomplete Imports", message: String(localized: "Removal stopped: \(error.localizedDescription)"))
            }
            isPurgingIncompleteImports = false
        }
    }

    private func clearCache() {
        guard let archiveCache else { return }
        isClearingCache = true
        Task {
            do {
                try await archiveCache.removeAll()
                outcome = SettingsOutcome(title: "Cache", message: String(localized: "Local cache cleared."))
            } catch {
                outcome = SettingsOutcome(title: "Cache", message: String(localized: "Cache clearing stopped: \(error.localizedDescription)"))
            }
            await refreshCacheSize()
            isClearingCache = false
        }
    }

    private func refreshCacheSize() async {
        guard let archiveCache else {
            cacheSize = 0
            return
        }
        cacheSize = try? await archiveCache.currentSize()
    }

    private var defaultBackupName: String {
        ArchiveBackupPackage.defaultFileName()
    }

    private func prepareBackup() {
        guard let archiveBackupService else { return }
        isPreparingBackup = true
        Task {
            cleanupPreparedBackup()
            // Staged in its own directory rather than directly in the temporary directory: the
            // export operation writes its own copy into the temporary directory, and an identically
            // named package there collides with the source it is copying from.
            let container = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveLeafBackup-\(UUID().uuidString)", isDirectory: true)
            let packageURL = container
                .appendingPathComponent(defaultBackupName)
                .appendingPathExtension(ArchiveBackupPackage.pathExtension)
            do {
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                _ = try await archiveBackupService.exportArchive(to: packageURL)
                preparedBackup = ArchiveBackupTransfer(packageURL: packageURL)
                isExportingBackup = true
            } catch {
                outcome = SettingsOutcome(title: "Backup", message: String(localized: "Backup stopped: \(error.localizedDescription)"))
            }
            isPreparingBackup = false
        }
    }

    private func finishBackupExport(_ result: Result<URL, any Error>) {
        defer { cleanupPreparedBackup() }
        switch result {
        case .success:
            outcome = SettingsOutcome(title: "Backup", message: String(localized: "Backup exported."))
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                outcome = SettingsOutcome(title: "Backup", message: String(localized: "Backup export stopped: \(error.localizedDescription)"))
            }
        }
    }

    /// Held between choosing a package and confirming, so the confirmation can describe what is
    /// about to be written and the security-scoped access stays open until the write finishes.
    private struct PendingRestore {
        let plan: ArchiveBackupRestorePlan
        let isSecurityScoped: Bool

        var packageURL: URL { plan.packageURL }

        var summary: String {
            String(
                localized:
                    "Writes \(plan.manifest.folders.count) folders and \(plan.manifest.files.count) files into your Archive."
            )
        }
    }

    private func inspectRestore(_ result: Result<URL, any Error>) {
        guard let archiveBackupService else { return }
        let packageURL: URL
        switch result {
        case .success(let url):
            packageURL = url
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                outcome = SettingsOutcome(title: "Backup", message: String(localized: "Backup could not be opened: \(error.localizedDescription)"))
            }
            return
        }

        isInspectingRestore = true
        Task {
            let isSecurityScoped = packageURL.startAccessingSecurityScopedResource()
            do {
                // prepareRestore also rejects a non-empty Archive, so the requirement surfaces
                // before the user is asked to confirm anything.
                // The plan carries the checking forward, so confirming does not read the package a
                // second time.
                let plan = try await archiveBackupService.prepareRestore(from: packageURL)
                pendingRestore = PendingRestore(plan: plan, isSecurityScoped: isSecurityScoped)
            } catch {
                if isSecurityScoped { packageURL.stopAccessingSecurityScopedResource() }
                outcome = SettingsOutcome(title: "Backup", message: String(localized: "Restore stopped: \(error.localizedDescription)"))
            }
            isInspectingRestore = false
        }
    }

    private func performRestore() {
        guard let archiveBackupService, let pending = pendingRestore else { return }
        pendingRestore = nil
        isRestoring = true
        Task {
            defer {
                if pending.isSecurityScoped {
                    pending.packageURL.stopAccessingSecurityScopedResource()
                }
                isRestoring = false
            }
            do {
                let result = try await archiveBackupService.restore(pending.plan)
                outcome = SettingsOutcome(title: "Backup", message: String(
                    localized:
                        "Restored \(result.restoredFolderCount) folders and \(result.restoredFileCount) files."
                ))
                NotificationCenter.default.post(
                    name: .archiveLeafArchiveDidReplace,
                    object: result.restoredSnapshot
                )
            } catch {
                outcome = SettingsOutcome(title: "Backup", message: String(localized: "Restore stopped: \(error.localizedDescription)"))
            }
        }
    }

    private func finishPendingRestore() {
        if let pending = pendingRestore, pending.isSecurityScoped {
            pending.packageURL.stopAccessingSecurityScopedResource()
        }
        pendingRestore = nil
    }

    private func importBookmarks(_ result: Result<URL, any Error>) {
        guard let bookmarkImporter else { return }
        let source = bookmarkImportSource
        let fileURL: URL
        switch result {
        case .success(let url):
            fileURL = url
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                outcome = SettingsOutcome(title: "Import Bookmarks", message: String(
                    localized: "The export could not be opened: \(error.localizedDescription)"
                ))
            }
            return
        }

        isImportingBookmarks = true
        Task {
            defer { isImportingBookmarks = false }
            do {
                let summary = try await bookmarkImporter.importBookmarks(from: fileURL, source: source)
                outcome = SettingsOutcome(title: "Import Bookmarks", message: Self.summaryMessage(for: summary))
                // The same hand-off a restore uses. The shelf takes the archive this import
                // produced rather than reading CloudKit, whose index trails its own writes.
                NotificationCenter.default.post(
                    name: .archiveLeafArchiveDidReplace,
                    object: summary.snapshot
                )
            } catch {
                outcome = SettingsOutcome(title: "Import Bookmarks", message: String(
                    localized: "Import stopped: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Every outcome, in one sentence each. A count of what came in, alone, reads as a loss when
    /// most of an export is pages the shelf already holds.
    private static func summaryMessage(for summary: BookmarkImportSummary) -> String {
        var lines = [
            String(localized: "Imported \(summary.importedCount) bookmarks into \(summary.source.name).")
        ]
        if summary.duplicateCount > 0 {
            lines.append(
                String(localized: "Skipped \(summary.duplicateCount) already on your shelf.")
            )
        }
        if summary.unreadableCount > 0 {
            lines.append(
                String(localized: "Skipped \(summary.unreadableCount) without a usable web address.")
            )
        }
        if !summary.failures.isEmpty {
            lines.append(String(localized: "\(summary.failures.count) could not be stored:"))
            lines.append(contentsOf: summary.failures.prefix(5))
        }
        return lines.joined(separator: "\n")
    }

    private func cleanupPreparedBackup() {
        if let packageURL = preparedBackup?.packageURL {
            try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent())
        }
        preparedBackup = nil
    }
}

#Preview {
    ArchiveLeafSettingsView()
}
