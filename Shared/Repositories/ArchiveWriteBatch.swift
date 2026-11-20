import Foundation

/// How many records go into one write, decided by what they carry rather than by counting them.
///
/// A fixed count is wrong at both ends when the records carry payloads. Twenty bookmarks are about
/// five kilobytes — a round trip spent on an all but empty request, and a bookmark export is
/// thousands of them. Twenty videos are gigabytes, which is a request no server should be handed.
/// The same number produced both.
///
/// Neither limit here is a discovery. The count is the one every other record type in this archive
/// already writes at, and the byte budget is below what the import path could already put in a
/// single request, so a batch can only come out smaller than it used to be — never larger.
///
/// A single item over the budget is written on its own rather than dropped: the budget decides how
/// things are grouped, and refusing a file is the import's decision, made earlier and elsewhere.
enum ArchiveWriteBatch {
    static func split<Item>(
        _ items: [Item],
        maximumCount: Int,
        maximumBytes: Int64,
        bytes: (Item) -> Int64
    ) -> [[Item]] {
        guard maximumCount > 0 else { return items.isEmpty ? [] : [items] }

        var batches: [[Item]] = []
        var current: [Item] = []
        var currentBytes: Int64 = 0

        for item in items {
            let itemBytes = max(0, bytes(item))
            let isFull = current.count >= maximumCount
            let (projected, overflow) = currentBytes.addingReportingOverflow(itemBytes)
            let wouldExceed = overflow || projected > maximumBytes
            if !current.isEmpty, isFull || wouldExceed {
                batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(item)
            currentBytes = currentBytes.addingReportingOverflow(itemBytes).partialValue
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }
}
