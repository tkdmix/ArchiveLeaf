import SwiftUI

struct FolderDestinationPicker: View {
    let title: LocalizedStringKey
    let folders: [ArchiveFolder]
    @Binding var selection: UUID?
    /// What "no folder" is called here. A folder placed there sits at the top of the tree; a file
    /// placed there is listed under Unsorted. Same value, two names, because the reader meets it
    /// as two different rows in the folder pane.
    var rootLabel: LocalizedStringKey = "Unsorted Files"

    var body: some View {
        Picker(title, selection: $selection) {
            Text(rootLabel).tag(nil as UUID?)
            ForEach(folderChoices, id: \.folder.id) { choice in
                Text(choice.path).tag(Optional(choice.folder.id))
            }
        }
    }

    private var folderChoices: [(folder: ArchiveFolder, path: String)] {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        return folders
            .map { folder in
                (folder, folderPath(folder, foldersByID: foldersByID))
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func folderPath(
        _ folder: ArchiveFolder,
        foldersByID: [UUID: ArchiveFolder]
    ) -> String {
        var components = [folder.name]
        var parentID = folder.parentFolderID
        var visited = Set([folder.id])
        while let id = parentID,
              visited.insert(id).inserted,
              let parent = foldersByID[id] {
            components.append(parent.name)
            parentID = parent.parentFolderID
        }
        return components.reversed().joined(separator: " / ")
    }
}
