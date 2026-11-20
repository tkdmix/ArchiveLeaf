import Foundation

/// A presentation-only hierarchy derived from slash-separated tag names.
///
/// The archive continues to store one `ArchiveTag` with one name. These nodes are rebuilt for the
/// UI, so changing the presentation later never requires a CloudKit or backup migration.
struct TagPathNode: Identifiable, Hashable, Sendable {
    /// The folded path, which is how a row is addressed and matched.
    let id: String
    /// The path as it was typed, which is how a row is named and stored.
    let displayPath: String
    let name: String
    let tag: ArchiveTag?
    let children: [TagPathNode]
    /// The files carrying the tag stored at this step, and no others.
    ///
    /// A child's files used to be counted here as well, so that the number beside a row and the
    /// list behind it agreed while the list gathered every descendant. The list no longer does:
    /// a step of the tree shows the steps under it and the files given that step's own name, the
    /// way a folder shows its folders and its files. Gathering descendants here again would put
    /// the number back at odds with the pane.
    let fileIDs: Set<UUID>

    /// **The number beside any row is the number of rows that row opens onto**, which is the
    /// definition the folders already use: the steps below this one, and the files named by it.
    var itemCount: Int { children.count + fileIDs.count }
    var selfAndDescendants: [TagPathNode] { [self] + children.flatMap(\.selfAndDescendants) }
    var outlineChildren: [TagPathNode]? { children.isEmpty ? nil : children }

    static func tree(tags: [ArchiveTag], files: [ArchiveFile]) -> [TagPathNode] {
        let fileIDsByTag = Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag.id, Set(files.lazy.filter { $0.tagIDs.contains(tag.id) }.map(\.id)))
        })
        let root = MutableTagPathNode(name: "", path: "")

        for tag in tags.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let split = tag.name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            // A malformed value from an older build must remain visible and repairable. Only new
            // input is rejected; existing archive data is never hidden by a presentation rule.
            let components = split.isEmpty || split.contains(where: { $0.isEmpty }) ? [tag.name] : split
            var parent = root
            var pathComponents: [String] = []
            for component in components {
                pathComponents.append(component)
                let key = foldedKey(component)
                if parent.children[key] == nil {
                    parent.children[key] = MutableTagPathNode(
                        name: component,
                        path: pathComponents.joined(separator: "/")
                    )
                }
                parent = parent.children[key]!
            }
            // Only the step the tag was actually stored under. `Dev` exists because `Dev/Xcode`
            // does, and carries no files of its own until something is tagged `Dev`.
            parent.fileIDs.formUnion(fileIDsByTag[tag.id] ?? [])
            parent.tag = tag
        }

        return root.frozenChildren
    }

    /// How one step of a tag's path is compared. Two tags whose names differ only in case or in
    /// accents are one row in the tree, so anything asking "is this tag under that one?" has to
    /// ask it the same way the tree does.
    static func foldedKey(_ component: String) -> String {
        component.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func normalizedName(_ name: String) -> String? {
        let components = name.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        return components.joined(separator: "/")
    }

    static func isValidName(_ name: String) -> Bool {
        normalizedName(name) != nil
    }
}

private final class MutableTagPathNode {
    let name: String
    let path: String
    var tag: ArchiveTag?
    var children: [String: MutableTagPathNode] = [:]
    var fileIDs: Set<UUID> = []

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    var frozenChildren: [TagPathNode] {
        children.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { child in
                TagPathNode(
                    id: child.path.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    ),
                    displayPath: child.path,
                    name: child.name,
                    tag: child.tag,
                    children: child.frozenChildren,
                    fileIDs: child.fileIDs
                )
            }
    }
}
