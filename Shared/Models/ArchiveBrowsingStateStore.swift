import Foundation

/// Where the reader was, written down so that opening the app again puts them back.
///
/// Coming back to the top of the archive every launch made the app forget a working session that
/// the reader had not finished. What is kept is only the place — not the file that was open, not
/// what was selected — because those belong to the moment rather than to the archive.
///
/// This is a device's own note to itself and deliberately not part of the archive: the same person
/// on a Mac and on a phone is usually in two different places, and neither should drag the other
/// along.
struct ArchiveBrowsingStateStore {
    private let defaults: UserDefaults
    private let key: String
    /// False against the in-memory sample. That archive is built afresh at every launch, so there
    /// is no previous session to return to — and a test that inherited where the last test finished
    /// would not be a test of anything repeatable.
    private let remembers: Bool

    init(
        defaults: UserDefaults = .standard,
        key: String = "ArchiveLeaf.browsingState",
        remembers: Bool? = nil
    ) {
        self.defaults = defaults
        self.key = key
        self.remembers = remembers ?? (
            ProcessInfo.processInfo.environment["ARCHIVELEAF_DATA_SOURCE"]?.lowercased() != "memory"
        )
    }

    /// What was written last, or a fresh state where nothing was written or what was written can no
    /// longer be read. A note this device cannot understand is not worth an error: it is one launch
    /// that begins at the beginning.
    func load() -> ArchiveBrowsingState {
        guard remembers,
              let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(ArchiveBrowsingState.self, from: data) else {
            return ArchiveBrowsingState()
        }
        return state
    }

    func save(_ state: ArchiveBrowsingState) {
        guard remembers, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
