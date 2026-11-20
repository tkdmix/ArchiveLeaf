import Foundation

/// Pure restoration choices for the shelf UI. The supplied snapshot is the visible shelf,
/// not raw metadata: a folder hidden by a discarded ancestor is not a usable destination.
enum ArchiveRestoration {
    enum Destination: Equatable { case root, folder(UUID), recovery }
    struct RecoveryFolder { let folder: ArchiveFolder; let needsCreation: Bool }

    static func destination(originalParentID: UUID?, in visible: ArchiveSnapshot) -> Destination {
        guard let id = originalParentID else { return .root }
        return visible.folders.contains(where: { $0.id == id && !$0.isTrashed }) ? .folder(id) : .recovery
    }

    static func recoveryFolder(in visible: ArchiveSnapshot, now: Date = .now) -> RecoveryFolder {
        let baseName = "Recovered Items"
        if let existing = visible.folders.first(where: {
            guard $0.parentFolderID == nil, !$0.isTrashed else { return false }
            let name = ArchiveRules.normalizedName($0.name)
            return name == ArchiveRules.normalizedName(baseName)
                || name.hasPrefix(ArchiveRules.normalizedName("\(baseName) ("))
        }) { return RecoveryFolder(folder: existing, needsCreation: false) }
        let occupied = Set(visible.folders.filter { $0.parentFolderID == nil }.map { ArchiveRules.normalizedName($0.name) }
            + visible.files.filter { $0.parentFolderID == nil }.map { ArchiveRules.normalizedName($0.displayName) })
        var name = baseName, suffix = 2
        while occupied.contains(ArchiveRules.normalizedName(name)) {
            name = "\(baseName) (\(suffix))"; suffix += 1
        }
        return RecoveryFolder(folder: ArchiveFolder(name: name, createdAt: now, updatedAt: now), needsCreation: true)
    }

    static func availableFileName(for file: ArchiveFile, in parentID: UUID?, visible: ArchiveSnapshot) -> String? {
        let current = file.displayName
        let occupied = Set(visible.folders.filter { $0.parentFolderID == parentID }.map { ArchiveRules.normalizedName($0.name) }
            + visible.files.filter { $0.parentFolderID == parentID }.map { ArchiveRules.normalizedName($0.displayName) })
        guard occupied.contains(ArchiveRules.normalizedName(current)) else { return file.userDefinedName }
        var suffix = 1
        while true {
            let name = suffix == 1 ? "\(current) (Recovered)" : "\(current) (Recovered \(suffix))"
            if !occupied.contains(ArchiveRules.normalizedName(name)) { return name }
            suffix += 1
        }
    }
}
