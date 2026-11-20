import SwiftUI

/// How a list of files is ordered. Shared so that every list offering it offers the same one.
///
/// Four criteria, each also its own switch: choosing the one already in force turns the order
/// around. The arrow beside it is both the tick and the direction, so one glance answers "by what"
/// and "which way" together, and the pair does not need a second row of controls to itself.
struct ArchiveSortMenu: View {
    @Bindable var viewModel: ArchiveViewModel
    /// Which criteria this list can be arranged by. All four where files are listed; a list of
    /// folders offers only the two that mean anything to a folder, because a folder has neither a
    /// format nor a size. The archive keeps one order for everything, so choosing here changes it
    /// everywhere — what differs is only which choices a given list can honestly offer.
    var modes: [ArchiveSortMode] = ArchiveSortMode.allCases

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            ForEach(modes) { mode in
                Button {
                    if viewModel.sortMode == mode {
                        viewModel.sortAscending.toggle()
                    } else {
                        viewModel.sortMode = mode
                    }
                } label: {
                    if viewModel.sortMode == mode {
                        Label(
                            mode.title,
                            systemImage: viewModel.sortAscending ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(mode.title)
                    }
                }
            }
        }
    }
}
