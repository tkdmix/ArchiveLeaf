import Foundation

/// A compact-width navigation route. IDs keep the route stable while CloudKit-backed metadata
/// values are replaced after rename, move, favorite, and display-setting changes.
enum ArchiveRoute: Hashable, Sendable {
    case folder(UUID)
    /// The files that sit in no folder. A folder in every way the reader meets it, but one with no
    /// record of its own, so it cannot be named by id like the others.
    case unsorted
    /// One step of the tag tree, named by its path. Half those steps are not tags of their own —
    /// `Dev` exists because `Dev/Xcode` does — so an id would not reach them.
    case tag(path: String)
    case file(UUID)
}

/// The four areas the archive is browsed through: a tab each on a compact width, and a group of
/// sidebar rows each at regular width.
///
/// Backed by strings because where the reader was is written down between launches, and a number
/// would silently mean a different area the moment the order of these cases changed.
enum ArchivePrimarySection: String, Hashable, Sendable, Codable {
    case folders
    case favorites
    case tags
    case trash
}

/// The location reached by popping a split-view column back to its root.
func archiveRootLocation(for location: ArchiveBrowsingLocation) -> ArchiveBrowsingLocation {
    switch location {
    case .folders, .unsorted, .folder: return .folders
    case .favorites: return .favorites
    case .tag: return .tag(path: "")
    case .trash: return .trash
    }
}

/// Derives the split column's stack from one browsing location. File focus deliberately has no
/// route: the split view presents it in the detail column instead of pushing the content column.
func archiveRoutePath(
    for location: ArchiveBrowsingLocation,
    folderIDs: [UUID],
    tagPaths: [String]
) -> [ArchiveRoute] {
    switch location {
    case .folders, .favorites, .tag(path: ""), .trash:
        return []
    case .unsorted:
        return [.unsorted]
    case .folder:
        return folderIDs.map { .folder($0) }
    case .tag:
        return tagPaths.map { .tag(path: $0) }
    }
}

/// Translates a stack pop or non-file route into its canonical location. A file route is handled
/// separately because it changes focus without changing the current list location.
func archiveBrowsingLocation(
    forColumnPath path: [ArchiveRoute],
    from currentLocation: ArchiveBrowsingLocation
) -> ArchiveBrowsingLocation? {
    guard let route = path.last else { return archiveRootLocation(for: currentLocation) }

    switch route {
    case .folder(let id): return .folder(id)
    case .unsorted: return .unsorted
    case .tag(let path): return .tag(path: path)
    case .file: return nil
    }
}
