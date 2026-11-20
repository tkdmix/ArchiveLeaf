import SwiftUI
import UniformTypeIdentifiers

/// Where the file list is looking: a folder, or one of the places that gather files from across
/// the archive.
///
/// The Mac's outline speaks in these; the iPad's sidebar no longer does. There, the sidebar chooses
/// one of the four areas and the column beside it carries the tree — the arrangement the phone has
/// always had, and the one whose rows can actually be chosen.
enum ArchiveSource: Hashable, Sendable {
    /// The heading the folders hang from, which is the archive's own first level.
    case folders
    /// nil is Unsorted: the files in no folder at all.
    case folder(UUID?)
    case favorites
    /// The files under one step of the tag tree, gathered from wherever in the archive they sit.
    /// The empty path is the heading the tags hang from — everything carrying any tag.
    case tag(path: String)
    case trash
}

/// Which folders are open, remembered across launches.
///
/// A folder pane the user has arranged is worth as much as the arrangement itself; coming back to
/// everything closed means finding the same place again every time.
@Observable
@MainActor
final class FolderExpansion {
    private static let defaultsKey = "ArchiveLeaf.expandedFolders"
    /// The archive's own row, which has no folder to name it.
    static let rootKey = "root"
    /// The row the tags hang from, which is not a folder either.
    static let tagsKey = "tags"

    private var open: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey)
        open = Set(stored ?? [Self.rootKey])
    }

    func isOpen(_ folderID: UUID?) -> Bool {
        isOpen(key: key(for: folderID))
    }

    func setOpen(_ isOpen: Bool, for folderID: UUID?) {
        setOpen(isOpen, key: key(for: folderID))
    }

    /// Keyed by name rather than by folder, for the rows that stand for something else.
    func isOpen(key: String) -> Bool {
        open.contains(key)
    }

    func setOpen(_ isOpen: Bool, key: String) {
        if isOpen {
            open.insert(key)
        } else {
            open.remove(key)
        }
        UserDefaults.standard.set(Array(open), forKey: Self.defaultsKey)
    }

    private func key(for folderID: UUID?) -> String {
        folderID?.uuidString ?? Self.rootKey
    }

    func binding(for folderID: UUID?) -> Binding<Bool> {
        binding(key: key(for: folderID))
    }

    func binding(key: String) -> Binding<Bool> {
        Binding(
            get: { self.open.contains(key) },
            set: { isOpen in
                if isOpen {
                    self.open.insert(key)
                } else {
                    self.open.remove(key)
                }
                UserDefaults.standard.set(Array(self.open), forKey: Self.defaultsKey)
            }
        )
    }
}
