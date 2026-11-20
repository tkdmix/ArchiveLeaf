import Foundation

/// Whether the reader has asked for the shelf to be locked.
///
/// A device's own note to itself, like where the reader was, and deliberately not part of the
/// archive. Locking a phone that travels and leaving a Mac at home open is a reasonable thing to
/// want, and syncing this would take that choice away.
struct ShelfLockSettingsStore {
    private let defaults: UserDefaults
    private let key: String
    /// False against the in-memory sample, which is what the automated runs use. A lock that a test
    /// cannot answer stops the test at the first screen, and a setting left behind by a previous
    /// run would stop it on a machine where nobody changed anything.
    private let remembers: Bool

    init(
        defaults: UserDefaults = .standard,
        key: String = "ArchiveLeaf.shelfLock.isEnabled",
        remembers: Bool? = nil
    ) {
        self.defaults = defaults
        self.key = key
        self.remembers = remembers ?? (
            ProcessInfo.processInfo.environment["ARCHIVELEAF_DATA_SOURCE"]?.lowercased() != "memory"
        )
    }

    /// Off until the reader turns it on. A shelf that asked for a face the first time it was opened
    /// would be answering a question nobody had asked yet.
    var isEnabled: Bool {
        guard remembers else { return false }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool) {
        guard remembers else { return }
        defaults.set(enabled, forKey: key)
    }
}
