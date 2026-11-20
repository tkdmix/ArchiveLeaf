import Foundation

/// The archive arranged for the questions the screens actually ask.
///
/// Every list on screen used to answer itself by walking the whole archive: the files in this
/// folder, the number beside that row, everything carrying this tag, everything starred. One walk
/// is cheap; a walk per row, on every redraw, is not. A folder tree of fifty rows over a thousand
/// files asked fifty thousand questions each time the screen was drawn, and nothing about that
/// depends on the network — it is the price of looking at the archive at all.
///
/// So the answers are arranged once, when the archive changes, and looked up afterwards. Built from
/// a value and holding no reference to the model it came from, which is what lets it be tested for
/// what it is: given these files, these are the answers.
struct ArchiveIndex: Sendable {
    private(set) var filesByID: [UUID: ArchiveFile] = [:]
    private(set) var foldersByID: [UUID: ArchiveFolder] = [:]
    /// Keyed by the folder a thing sits in, with `nil` for the archive's own root — which is a real
    /// key here, not an absence: files belonging to no folder are what Unsorted shows.
    private(set) var filesByParent: [UUID?: [ArchiveFile]] = [:]
    private(set) var foldersByParent: [UUID?: [ArchiveFolder]] = [:]
    private(set) var fileIDsByTag: [UUID: [UUID]] = [:]
    private(set) var favorites: [ArchiveFile] = []
    /// Files carrying any tag at all, which is what the Tags heading gathers.
    private(set) var tagged: [ArchiveFile] = []

    init() {}

    init(files: [ArchiveFile], folders: [ArchiveFolder]) {
        filesByID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        for file in files {
            filesByParent[file.parentFolderID, default: []].append(file)
            for tagID in file.tagIDs {
                fileIDsByTag[tagID, default: []].append(file.id)
            }
            if file.isFavorite { favorites.append(file) }
            if !file.tagIDs.isEmpty { tagged.append(file) }
        }
        for folder in folders {
            foldersByParent[folder.parentFolderID, default: []].append(folder)
        }
    }

    func files(inFolderWithID parentFolderID: UUID?) -> [ArchiveFile] {
        filesByParent[parentFolderID] ?? []
    }

    func folders(inFolderWithID parentFolderID: UUID?) -> [ArchiveFolder] {
        foldersByParent[parentFolderID] ?? []
    }

    /// What opening this row shows: the folders in it, and the files in it. The archive's own root
    /// counts only files, because the folders at the top of the tree are not inside Unsorted.
    func itemCount(inFolderWithID parentFolderID: UUID?) -> Int {
        let fileCount = files(inFolderWithID: parentFolderID).count
        guard parentFolderID != nil else { return fileCount }
        return folders(inFolderWithID: parentFolderID).count + fileCount
    }

    /// Everything carrying any of these tags, each file once however many of them it carries.
    func files(carryingAnyOf tagIDs: Set<UUID>) -> [ArchiveFile] {
        var seen = Set<UUID>()
        var gathered: [ArchiveFile] = []
        for tagID in tagIDs {
            for fileID in fileIDsByTag[tagID] ?? [] where seen.insert(fileID).inserted {
                if let file = filesByID[fileID] { gathered.append(file) }
            }
        }
        return gathered
    }
}
