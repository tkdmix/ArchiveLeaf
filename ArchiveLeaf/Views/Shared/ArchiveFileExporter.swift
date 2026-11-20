import Foundation

/// Writes an archived file out as a real file, for handing to somewhere else.
///
/// Every archived file can do this: it is bytes and a name, and neither depends on how the file
/// happens to be displayed.
///
/// Deliberately away from the view model, which is main-actor bound. A share sheet asks for the
/// file while a menu or picker is running its own event loop, and the main actor cannot answer
/// until that finishes — which showed up as several seconds of nothing after choosing Share.
struct ArchiveFileExporter: Sendable {
    let contentLoader: any FileContentLoading

    func fileURL(for file: ArchiveFile) async -> URL? {
        guard let data = try? await contentLoader.originalData(for: file) else { return nil }
        return try? PreviewFileStore.write(data, named: file.sidebarDisplayName, for: file.id)
    }
}
