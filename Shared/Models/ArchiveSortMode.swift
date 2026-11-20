import Foundation

/// How a list of files is ordered.
///
/// Four, and each answers a question that can be asked of any file. Ordering by hand is gone: a
/// file's place was kept per folder, which said nothing about a list gathered by an attribute, and
/// the archive is read rather than arranged. The source's modification date is gone with it —
/// files arriving through the share sheet are written out first, so what was recorded was the
/// moment of sharing, and a criterion that means one thing on the Mac and another on the phone is
/// worse than none. It is still shown under Info, where it says whose date it is.
enum ArchiveSortMode: String, CaseIterable, Identifiable, Sendable {
    case displayName
    case importedAt
    case format
    case fileSize

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .displayName: "Name"
        case .importedAt: "Date"
        case .format: "File Format"
        case .fileSize: "File Size"
        }
    }
}
