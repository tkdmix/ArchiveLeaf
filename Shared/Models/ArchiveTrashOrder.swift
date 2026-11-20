import Foundation

/// How the Trash is arranged.
///
/// Two ways, and only two. Format and Size sort files and say nothing about a folder, and the Trash
/// is the one list where both kinds are mixed together by design. What a person does here is find
/// the thing they just lost — by when it went, or by what it is called.
enum ArchiveTrashOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// When it was thrown away, most recent first. The way a real bin is read, and the way this one
    /// opens every time.
    case discarded
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discarded: String(localized: "Date Discarded")
        case .name: String(localized: "Name")
        }
    }

    /// Which way round the arrangement begins when this one is chosen. Newest first for a date,
    /// A to Z for a name — each the direction a person means when they ask for it.
    var beginsAscending: Bool {
        switch self {
        case .discarded: false
        case .name: true
        }
    }
}

enum ArchiveTrashArrangement {
    /// Sorted rather than trusted: the archive answers from an index that returns records in no
    /// particular order, so without this the Trash arranged itself differently after every read.
    ///
    /// One list, both kinds together. Everywhere else a folder comes before a file because that is
    /// the shape of the place being looked at; here the shape that matters is time, and a heading
    /// for each kind would put the newest item somewhere in the middle of the screen.
    static func ordered(
        _ items: [ArchiveItem],
        by order: ArchiveTrashOrder,
        ascending: Bool
    ) -> [ArchiveItem] {
        items.sorted { first, second in
            let isBefore = switch order {
            case .discarded: discardedAt(first) < discardedAt(second)
            case .name:
                first.listedName.localizedStandardCompare(second.listedName) == .orderedAscending
            }
            // A stable answer for two things that compare the same, so a redraw cannot shuffle them.
            if isBefore == isAfter(first, second, by: order) {
                return first.id.uuidString < second.id.uuidString
            }
            return ascending ? isBefore : !isBefore
        }
    }

    private static func isAfter(
        _ first: ArchiveItem,
        _ second: ArchiveItem,
        by order: ArchiveTrashOrder
    ) -> Bool {
        switch order {
        case .discarded: discardedAt(first) > discardedAt(second)
        case .name:
            first.listedName.localizedStandardCompare(second.listedName) == .orderedDescending
        }
    }

    private static func discardedAt(_ item: ArchiveItem) -> Date {
        switch item {
        case .folder(let folder): folder.trashedAt ?? .distantPast
        case .file(let file): file.trashedAt ?? .distantPast
        }
    }
}
