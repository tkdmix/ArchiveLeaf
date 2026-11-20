import SwiftUI

/// Looking through the pictures of a folder: the one on screen, its neighbours, and the movement
/// between them.
///
/// Loads for itself rather than going through the single-file content path. Following a finger from
/// one picture to the next means the neighbour has to already be in hand when the gesture starts,
/// which a view holding one file's content at a time cannot offer.
struct ImageBrowserView: View {
    let file: ArchiveFile
    let viewModel: ArchiveViewModel
    @Binding var zoomCommand: ImageZoomCommand?
    /// Reported back so the toolbar and the Info popover describe the picture actually on screen.
    @Binding var displayedImage: LoadedImageContent?
    /// The same picture as a file on disk, which is the form sharing takes it in. Written here,
    /// where the picture and the file it came from are both in hand.
    @Binding var displayedFileURL: URL?
    let onShowFile: (UUID) -> Void

    @State private var selection: UUID
    @State private var contents: [UUID: LoadedImageContent] = [:]
    @State private var fileURLs: [UUID: URL] = [:]
    @State private var failure: String?

    /// How far either side of the picture on screen is kept loaded. One is what a gesture can
    /// reach; the rest is dropped so paging through a large folder does not accumulate.
    private static let neighbourhood = 1
    private static let retained = 2

    init(
        file: ArchiveFile,
        viewModel: ArchiveViewModel,
        zoomCommand: Binding<ImageZoomCommand?>,
        displayedImage: Binding<LoadedImageContent?>,
        displayedFileURL: Binding<URL?>,
        onShowFile: @escaping (UUID) -> Void
    ) {
        self.file = file
        self.viewModel = viewModel
        _zoomCommand = zoomCommand
        _displayedImage = displayedImage
        _displayedFileURL = displayedFileURL
        self.onShowFile = onShowFile
        _selection = State(initialValue: file.id)
    }

    /// The pictures this one sits among. A picture in the Trash sits among none — its folder no
    /// longer lists it — so it stands alone rather than not appearing at all.
    private var images: [ArchiveFile] {
        let neighbours = viewModel.files(in: file.parentFolderID)
            .filter { $0.effectiveDisplayFormat.isImage }
        return neighbours.contains { $0.id == file.id } ? neighbours : [file]
    }

    var body: some View {
        Group {
            pages
        }
        .task(id: selection) { await loadNeighbourhood() }
        .onChange(of: selection) { _, id in
            displayedImage = contents[id]
            displayedFileURL = fileURLs[id]
            failure = nil
            if id != file.id { onShowFile(id) }
            dropDistantPictures()
        }
        // The list alongside can also change the selection; the two have to agree either way.
        .onChange(of: file.id) { _, id in
            if id != selection { selection = id }
        }
    }

    #if os(macOS)
    /// `NSPageController` does the same job the paging `TabView` does on iOS: the neighbour
    /// follows the trackpad rather than arriving once a fixed distance is passed.
    private var pages: some View {
        PagingImageView(
            images: images,
            contents: contents,
            selection: $selection,
            zoomCommand: $zoomCommand
        )
        .overlay {
            if contents[selection] == nil {
                if let failure {
                    ContentUnavailableView(
                        "Content Could Not Be Loaded",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure)
                    )
                } else {
                    ProgressView()
                }
            }
        }
    }
    #else
    /// A paging scroll view holding one zooming page per picture, so the neighbour arrives with
    /// the finger and can be abandoned halfway.
    private var pages: some View {
        ImagePagerView(
            pictureIDs: images.map(\.id),
            contents: contents,
            selection: $selection,
            zoomCommand: $zoomCommand
        )
        .overlay {
            if contents[selection] == nil {
                if let failure {
                    ContentUnavailableView(
                        "Content Could Not Be Loaded",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure)
                    )
                } else {
                    ProgressView()
                }
            }
        }
    }
    #endif

    /// The picture on screen first, then the ones a gesture can reach next.
    private func loadNeighbourhood() async {
        let list = images
        guard let index = list.firstIndex(where: { $0.id == selection }) else { return }
        let offsets = [0] + (1...Self.neighbourhood).flatMap { [$0, -$0] }
        for offset in offsets {
            let position = index + offset
            guard list.indices.contains(position) else { continue }
            let wanted = list[position]
            guard contents[wanted.id] == nil else { continue }
            do {
                if case .image(let image) = try await viewModel.loadContent(for: wanted) {
                    contents[wanted.id] = image
                    fileURLs[wanted.id] = try? PreviewFileStore.write(
                        image.data,
                        named: wanted.sidebarDisplayName,
                        for: wanted.id
                    )
                    if wanted.id == selection {
                        displayedImage = image
                        displayedFileURL = fileURLs[wanted.id]
                    }
                }
            } catch {
                if wanted.id == selection { failure = error.localizedDescription }
            }
        }
    }

    private func dropDistantPictures() {
        let list = images
        guard let index = list.firstIndex(where: { $0.id == selection }) else { return }
        let keep = Set(
            (index - Self.retained...index + Self.retained)
                .filter { list.indices.contains($0) }
                .map { list[$0].id }
        )
        contents = contents.filter { keep.contains($0.key) }
        fileURLs = fileURLs.filter { keep.contains($0.key) }
    }
}
