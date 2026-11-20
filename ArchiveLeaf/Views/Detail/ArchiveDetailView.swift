import SwiftUI
import AVKit
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ArchiveDetailView: View {
    let item: ArchiveItem?
    let viewModel: ArchiveViewModel
    var emptyNavigationTitle: LocalizedStringResource?
    /// Supplied where a list is showing alongside, so moving to the next picture also moves the
    /// highlight. Without one the change is kept here, which is all a pushed detail view can do.
    var onShowFile: ((UUID) -> Void)?
    @State private var shownFileID: UUID?
    /// How much room this pane has, which decides how much it tries to say when empty.
    @State private var paneWidth: CGFloat = 0

    var body: some View {
        Group {
            switch shownItem {
            case .folder(let folder):
                ContentUnavailableView(
                    folder.name,
                    systemImage: "folder",
                    description: Text("Folder details will appear here.")
                )
            case .file(let file):
                FileDetailView(
                    file: file,
                    viewModel: viewModel,
                    onShowFile: showFile
                )
            case nil:
                PaneNotice(
                    "No Selection",
                    systemImage: "archivebox",
                    description: "Select an item to see it here.",
                    width: paneWidth
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .measuringPaneWidth(into: $paneWidth)
        .navigationTitle(title)
        #if !os(macOS)
        // Said outright, because leaving the name out is not the same as leaving the room for it
        // out. With the title empty the bar still kept the line the title would have sat on —
        // measured on an iPad: 102 points tall with the controls occupying the first 44 of them,
        // so 52 points of nothing between the controls and the file. Inline, the bar is 50 and the
        // file begins where the controls end.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .documentControlsPlaceholder(isShown: !isShowingDocument)
        .onChange(of: item?.id) { _, _ in shownFileID = nil }
    }

    /// Whether the pane is showing a document, which is what carries the three of its own.
    private var isShowingDocument: Bool {
        if case .file = shownItem { true } else { false }
    }

    private var shownItem: ArchiveItem? {
        if let shownFileID, let file = viewModel.file(id: shownFileID) {
            return .file(file)
        }
        return item
    }

    private func showFile(_ id: UUID) {
        if let onShowFile {
            onShowFile(id)
        } else {
            shownFileID = id
        }
    }

    private var title: Text {
        guard let shownItem else {
            if let emptyNavigationTitle { return Text(emptyNavigationTitle) }
            return Text(verbatim: "")
        }
        #if !os(macOS)
        // No file names up here at all.
        //
        // A picture has been nameless since it started filling the screen, and the reason given for
        // it holds for everything else: whoever opened this chose it a moment ago from a list that
        // said its name. The bar then repeated that name over the document's own heading, and a
        // picture and a document disagreed about whether a viewer is titled.
        //
        // It buys no room — measured on a phone, the bar is 96 points tall with a title and 96
        // without, because it is there for the way back and for the document's own controls. What
        // it buys is one answer instead of two. The name is still a tap away under Info, and the
        // Mac keeps it, where the same words are the window's own name.
        if case .file = shownItem {
            return Text(verbatim: "")
        }
        #endif
        return Text(verbatim: shownItem.displayName)
    }
}

private struct FileDetailView: View {
    let file: ArchiveFile
    let viewModel: ArchiveViewModel
    let onShowFile: (UUID) -> Void

    var body: some View {
        ReadOnlyFileContentView(
            file: file,
            viewModel: viewModel,
            onShowFile: onShowFile
        )
    }
}

/// Which bytes are shown and how they are presented. Any of these changing must reload the content.
///
/// The file itself belongs here: this view keeps its state across a change of file — the detail
/// pane of a split view never rebuilds it — so leaving the identity out left the previous file's
/// content on screen under the new file's name.
private struct ContentPresentationKey: Equatable {
    let fileID: UUID
    let format: ImportedFormat
    let encoding: ArchiveTextEncoding?

    init(file: ArchiveFile) {
        fileID = file.id
        format = file.effectiveDisplayFormat
        encoding = file.effectiveTextEncoding
    }
}

/// A document ready to draw, and how it should be set.
private struct PresentedText {
    let text: AttributedString
    let isMonospaced: Bool
}

private struct ReadOnlyFileContentView: View {
    let file: ArchiveFile
    let viewModel: ArchiveViewModel
    let onShowFile: (UUID) -> Void
    @State private var state: ContentState = .loading
    @State private var isShowingInfo = false
    @State private var imageZoomCommand: ImageZoomCommand?
    @State private var pdfZoomCommand: PDFZoomCommand?
    /// The picture the browser has on screen, which runs ahead of `state` while it pages.
    @State private var displayedImage: LoadedImageContent?
    /// The picture on screen written out as a file, which is what sharing takes.
    @State private var displayedFileURL: URL?
    /// A bookmark is its URL. Unlike other imported files, sharing it hands that address to the
    /// receiving app rather than exporting its `.webloc` wrapper.
    @State private var bookmarkURL: URL?
    /// Whose URL that is. This view is not rebuilt when the pane is given another file, so the
    /// address of the one before is still here until the new one has been read — and answering a
    /// press with it opened the page the reader had just closed.
    @State private var bookmarkFileID: UUID?
    /// The document turned into its presented form once, when it loads. Doing it in the body meant
    /// re-parsing the whole file on every redraw, which is what made a long one feel slow.
    @State private var presented: PresentedText?
    @State private var browserURL: URL?
    @State private var pendingExternalURL: URL?
    @State private var isShowingSearch = false
    @State private var searchQuery = ""
    #if os(macOS)
    /// macOS keeps a compact toolbar for genuinely narrow panes. Mobile toolbars deliberately
    /// stay flat: the system decides any overflow from independent controls.
    @State private var paneWidth: CGFloat = 0
    #endif
    private let urlHandler = ArchiveURLHandler()

    private var isPicture: Bool { file.effectiveDisplayFormat.isImage }

    /// What a link means here, wherever it was pressed: in the archive's own browser if it can be,
    /// and otherwise only after asking. SwiftUI's links reach this through the `openURL`
    /// environment; a document's own links reach it through the text view's delegate, because a
    /// text view is not `Text` and does not consult that environment.
    private func open(_ url: URL) {
        if urlHandler.canOpenInApp(url) {
            #if os(macOS)
            browserURL = url
            #else
            // Not kept here. The page covers the whole app and outlives this pane, which iPad
            // rebuilds whenever the window changes shape.
            viewModel.openPage = url
            #endif
        } else {
            pendingExternalURL = url
        }
    }

    #if os(macOS)
    /// Whether the macOS pane is wide enough to carry every control without crowding the pane.
    private var hasRoomForEveryControl: Bool {
        // Geometry arrives just after the first toolbar pass. Start broad, then keep the controls
        // within a genuinely narrow macOS pane once its measured width is available.
        guard paneWidth > 0 else { return true }
        return paneWidth >= 300
    }
    #endif

    private var shareURL: URL? {
        isBookmark ? bookmarkURL : displayedFileURL
    }

    var body: some View {
        Group {
            #if os(macOS)
            if let browserURL {
                // A bookmark is nothing but its page, so there is nowhere to go back to and no
                // control offered for it. Every other document is still behind its links.
                ArchiveBrowserView(
                    url: browserURL,
                    onClose: isBookmark ? nil : { self.browserURL = nil }
                )
            } else {
                fileContent
            }
            #else
            // The page is not pane content here. It arrives full screen, over everything, and this
            // is what stands behind it while it does.
            fileContent
            #endif
        }
        #if os(macOS)
        .measuringPaneWidth(into: $paneWidth)
        #endif
        // Pressing the file already on screen. The pane is not rebuilt for it and the card must not
        // be redrawn, so nothing here reloads: the page is simply asked for again. Reached only
        // where the list stays beside the document, which is the only place the same row can be
        // pressed twice.
        .onChange(of: viewModel.chosenFileID) { _, _ in
            guard bookmarkFileID == file.id,
                  let bookmarkURL,
                  viewModel.takeChoice(of: file.id) else { return }
            open(bookmarkURL)
        }
        .task(id: ContentPresentationKey(file: file)) {
            browserURL = nil
            pendingExternalURL = nil
            imageZoomCommand = nil
            pdfZoomCommand = nil
            isShowingSearch = false
            searchQuery = ""
            // Pictures load through the browser, which needs their neighbours as well.
            guard !isPicture else {
                _ = viewModel.takeChoice(of: file.id)
                return
            }
            displayedImage = nil
            displayedFileURL = nil
            bookmarkURL = nil
            bookmarkFileID = nil
            presented = nil
            state = .loading
            do {
                let content = try await viewModel.loadContent(for: file)
                state = .loaded(content)
                // A bookmark is a URL and nothing else, so choosing one opens its page: no card to
                // press through on the way in. The choice is taken here rather than assumed,
                // because this also runs for a file restored at launch, which nobody chose today.
                //
                // Routed through `open` rather than set directly, so that a bookmark holding an
                // address no in-app browser accepts is handed outside like any other link instead
                // of failing silently here.
                if case .bookmark(let url) = content {
                    bookmarkURL = url
                    bookmarkFileID = file.id
                    if viewModel.takeChoice(of: file.id) { open(url) }
                } else {
                    _ = viewModel.takeChoice(of: file.id)
                    // Every non-bookmark format is shared as its imported bytes, so there is no
                    // re-encoding to worry about.
                    displayedFileURL = await viewModel.fileExporter.fileURL(for: file)
                }
                presented = await presentation(of: content)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        // Ordered by what it acts on, then by how often it is reached for. Everything here belongs
        // to the open document, so it follows the archive's own items and precedes Settings, which
        // the window keeps at the far end. Inspecting comes last.
        .toolbar {
            #if os(macOS)
            if hasRoomForEveryControl {
                if !file.isTrashed {
                    ToolbarItem {
                        Button(
                            file.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: file.isFavorite ? "star.fill" : "star"
                        ) {
                            Task { await viewModel.toggleFavorite(file.id) }
                        }
                    }
                }

                // How the document is being looked at. Only one of these ever applies: a picture
                // has a magnification, a document has a search.
                if file.effectiveDisplayFormat.supportsDocumentSearch {
                    ToolbarItem {
                        Button("Find", systemImage: "magnifyingglass") {
                            isShowingSearch.toggle()
                            if !isShowingSearch { searchQuery = "" }
                        }
                        .keyboardShortcut("f", modifiers: .command)
                    }
                }

                if isPDF {
                    ToolbarItemGroup {
                        pdfFitPageButton
                        pdfFitWidthButton
                    }
                }

                if displayedImage != nil {
                    ToolbarItemGroup {
                        #if os(macOS)
                        // Kept on the Mac, where a window has room for them and a mouse alone
                        // cannot pinch.
                        Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                            imageZoomCommand = .zoomOut
                        }
                        #endif

                        Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") {
                            imageZoomCommand = .fit
                        }

                        Button("Actual Size", systemImage: "1.magnifyingglass") {
                            imageZoomCommand = .actualSize
                        }

                        #if os(macOS)
                        Button("Zoom In", systemImage: "plus.magnifyingglass") {
                            imageZoomCommand = .zoomIn
                        }
                        #endif
                    }
                }

                if !file.isTrashed {
                    // The slot is kept while its shareable form is being readied, so the bar does
                    // not change shape a moment after the document appears.
                    ToolbarItem {
                        shareControl
                    }
                }

                ToolbarItem {
                    Button("Info", systemImage: "info.circle") {
                        isShowingInfo.toggle()
                    }
                    #if os(macOS)
                    .popover(isPresented: $isShowingInfo) {
                        FileMetadataView(
                            file: file,
                            tagNames: viewModel.tags(on: file).map(\.name),
                            loadedImage: displayedImage,
                            onDisplayFormatChange: { format in
                                Task { await viewModel.setDisplayFormat(format, for: file) }
                            },
                            onSourceEncodingChange: { encoding in
                                Task { await viewModel.setSourceEncoding(encoding, for: file) }
                            }
                        )
                    }
                    #endif
                }
            } else {
                // Narrow: a non-trashed file keeps the star, being the one act on a document that
                // is not about looking at it, and the rest waits behind one press. The pane is for
                // seeing the document, so the document keeps the room.
                if !file.isTrashed {
                    ToolbarItem {
                        Button(
                            file.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: file.isFavorite ? "star.fill" : "star"
                        ) {
                            Task { await viewModel.toggleFavorite(file.id) }
                        }
                    }
                }

                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        if file.effectiveDisplayFormat.supportsDocumentSearch {
                            Button("Find", systemImage: "magnifyingglass") {
                                isShowingSearch.toggle()
                                if !isShowingSearch { searchQuery = "" }
                            }
                        }

                        if isPDF {
                            pdfFitPageButton
                            pdfFitWidthButton
                        }

                        if displayedImage != nil {
                            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                                imageZoomCommand = .zoomOut
                            }
                            Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") {
                                imageZoomCommand = .fit
                            }
                            Button("Actual Size", systemImage: "1.magnifyingglass") {
                                imageZoomCommand = .actualSize
                            }
                            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                                imageZoomCommand = .zoomIn
                            }
                        }

                        if !file.isTrashed {
                            Divider()
                            shareControl
                        } else if file.effectiveDisplayFormat.supportsDocumentSearch || displayedImage != nil {
                            Divider()
                        }

                        Button("Info", systemImage: "info.circle") {
                            isShowingInfo.toggle()
                        }
                    }
                    #if os(macOS)
                    .popover(isPresented: $isShowingInfo) {
                        FileMetadataView(
                            file: file,
                            tagNames: viewModel.tags(on: file).map(\.name),
                            loadedImage: displayedImage,
                            onDisplayFormatChange: { format in
                                Task { await viewModel.setDisplayFormat(format, for: file) }
                            },
                            onSourceEncodingChange: { encoding in
                                Task { await viewModel.setSourceEncoding(encoding, for: file) }
                            }
                        )
                    }
                    #endif
                }
            }
            #else
            // Keep mobile document actions flat and in priority order. There is no app-defined
            // grouping or overflow policy here: the system can preserve, group, or elide controls
            // according to the available bar without changing their meaning.
            if !file.isTrashed {
                ToolbarItem {
                    Button(
                        file.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: file.isFavorite ? "star.fill" : "star"
                    ) {
                        Task { await viewModel.toggleFavorite(file.id) }
                    }
                }
            }

            if file.effectiveDisplayFormat.supportsDocumentSearch {
                ToolbarItem {
                    Button("Find", systemImage: "magnifyingglass") {
                        isShowingSearch.toggle()
                        if !isShowingSearch { searchQuery = "" }
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
            }

            if isPDF {
                ToolbarItem {
                    pdfFitPageButton
                }
                ToolbarItem {
                    pdfFitWidthButton
                }
            }

            if displayedImage != nil {
                ToolbarItem {
                    Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") {
                        imageZoomCommand = .fit
                    }
                }
                ToolbarItem {
                    Button("Actual Size", systemImage: "1.magnifyingglass") {
                        imageZoomCommand = .actualSize
                    }
                }
            }

            if !file.isTrashed {
                // Keep this slot while the shareable form is being readied, so opening a file does
                // not reshuffle the controls when its bytes finish loading.
                ToolbarItem {
                    shareControl
                }
            }

            ToolbarItem {
                Button("Info", systemImage: "info.circle") {
                    isShowingInfo.toggle()
                }
            }
            #endif
        }
        #if !os(macOS)
        // Not on the Info button, and not inside the toolbar at all.
        //
        // Choosing an encoding or a format reloads the document, and while it reloads this screen
        // shows the spinner instead — which takes the whole toolbar down with it, the Info button
        // included. iOS 26 animates a menu closing by morphing it back into the control it came
        // from, and with that control's window gone it does not shrug: it asserts, and the app is
        // killed. "Cannot morph from a view that is not in the hierarchy." Attached here, the panel
        // outlives the reload, so there is something to morph back into.
        .sheet(isPresented: $isShowingInfo) {
            FileMetadataView(
                file: file,
                tagNames: viewModel.tags(on: file).map(\.name),
                loadedImage: displayedImage,
                onDisplayFormatChange: { format in
                    Task { await viewModel.setDisplayFormat(format, for: file) }
                },
                onSourceEncodingChange: { encoding in
                    Task { await viewModel.setSourceEncoding(encoding, for: file) }
                }
            )
        }
        #endif
        .alert(
            "Display Format Could Not Be Saved",
            isPresented: Binding(
                get: { viewModel.displayFormatErrorMessage != nil },
                set: { if !$0 { viewModel.clearDisplayFormatError() } }
            )
        ) {
            Button("OK") { viewModel.clearDisplayFormatError() }
        } message: {
            Text(viewModel.displayFormatErrorMessage ?? "Unknown error")
        }
        .alert(
            "Encoding Could Not Be Saved",
            isPresented: Binding(
                get: { viewModel.sourceEncodingErrorMessage != nil },
                set: { if !$0 { viewModel.clearSourceEncodingError() } }
            )
        ) {
            Button("OK") { viewModel.clearSourceEncodingError() }
        } message: {
            Text(viewModel.sourceEncodingErrorMessage ?? "Unknown error")
        }
        .environment(\.openURL, OpenURLAction { url in
            open(url)
            return .handled
        })
        .confirmationDialog(
            "Open External Link?",
            isPresented: Binding(
                get: { pendingExternalURL != nil },
                set: { if !$0 { pendingExternalURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Open", role: .destructive) {
                if let url = pendingExternalURL { openOutsideArchiveLeaf(url) }
                pendingExternalURL = nil
            }
            Button("Cancel", role: .cancel) { pendingExternalURL = nil }
        } message: {
            Text(pendingExternalURL?.absoluteString ?? "")
        }
    }

    /// The file itself: the picture browser, or the document once it has loaded. Extracted because
    /// what stands in front of it differs by platform — a browser pane on the Mac, a full-screen
    /// presentation elsewhere — and a view builder cannot carry that difference through the middle
    /// of one `if` chain.
    @ViewBuilder
    private var fileContent: some View {
        if isPicture {
            ImageBrowserView(
                file: file,
                viewModel: viewModel,
                zoomCommand: $imageZoomCommand,
                displayedImage: $displayedImage,
                displayedFileURL: $displayedFileURL,
                onShowFile: onShowFile
            )
        } else {
            switch state {
            case .loading:
                ProgressView("Loading…")
            case .failed(let message):
                ContentUnavailableView(
                    "Content Could Not Be Loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded(let content):
                VStack(spacing: 0) {
                    if isShowingSearch, file.effectiveDisplayFormat.supportsDocumentSearch {
                        searchBar(for: content)
                        Divider()
                    }
                    contentView(content)
                }
            }
        }
    }

    private var isBookmark: Bool { file.effectiveDisplayFormat == .bookmark }

    private var isPDF: Bool { file.effectiveDisplayFormat.isPDF }

    /// The two ways a page is looked at, offered on every platform.
    ///
    /// PDFKit's own pinch reaches whatever magnification the reader asked for, but not back to a
    /// stated one, and a mouse cannot pinch at all. These two are the ones a reader means: the whole
    /// page, or the page as wide as the pane with the reading done by scrolling.
    private var pdfFitPageButton: some View {
        Button("Fit Page", systemImage: "arrow.down.right.and.arrow.up.left") {
            pdfZoomCommand = .fitPage
        }
    }

    private var pdfFitWidthButton: some View {
        Button("Fit Width", systemImage: "arrow.left.and.right") {
            pdfZoomCommand = .fitWidth
        }
    }

    @ViewBuilder
    private var shareControl: some View {
        if let shareURL {
            ShareLink(item: shareURL)
        } else {
            Button("Share", systemImage: "square.and.arrow.up") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private func contentView(_ content: LoadedFileContent) -> some View {
        if case .bookmark(let url) = content {
            #if os(macOS)
            // Reached only for the moment between the content arriving and the page taking over.
            ProgressView()
            #else
            // Behind the page, and where closing the page lands.
            BookmarkCardView(url: url) { open(url) }
            #endif
        } else if case .video(let video) = content {
            ReadOnlyVideoView(video: video)
        } else if case .pdf(let data) = content {
            ReadOnlyPDFView(data: data, zoomCommand: $pdfZoomCommand)
        } else if let presented {
            scrollableText(highlighted(presented.text), monospaced: presented.isMonospaced)
        } else {
            ProgressView()
        }
    }

    /// Off the main actor: turning a long document into an attributed string takes long enough to
    /// be felt, and nothing on screen depends on it until it is done.
    private nonisolated func presentation(of content: LoadedFileContent) async -> PresentedText? {
        if case .markdown(let source) = content {
            return await Task.detached(priority: .userInitiated) {
                PresentedText(
                    text: MarkdownAttributedText.attributedString(from: source),
                    isMonospaced: false
                )
            }.value
        }

        return await Task.detached(priority: .userInitiated) {
            let linkifier = CompleteURLLinkifier()
            switch content {
            case .plainText(let text):
                return PresentedText(text: linkifier.linkedText(text), isMonospaced: true)
            case .json(let text):
                return PresentedText(text: linkifier.linkedJSONValues(text), isMonospaced: true)
            case .markdown:
                return nil
            case .image:
                return nil
            case .bookmark:
                return nil
            case .video:
                return nil
            case .pdf:
                return nil
            }
        }.value
    }

    private func scrollableText(_ text: AttributedString, monospaced: Bool) -> some View {
        DocumentTextView(
            text: monospaced ? monospacedThroughout(text) : text,
            onOpenLink: open
        )
    }

    /// Plain text and JSON are set in a fixed pitch. Applied here rather than as a view modifier,
    /// which a text view does not answer to.
    @MainActor
    private func monospacedThroughout(_ text: AttributedString) -> AttributedString {
        var result = text
        let font = PlatformFont.monospacedSystemFont(
            ofSize: PlatformFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        #if os(macOS)
        let appKitText = NSMutableAttributedString(result)
        appKitText.addAttributes(
            [.font: font, .foregroundColor: NSColor.labelColor],
            range: NSRange(location: 0, length: appKitText.length)
        )
        result = AttributedString(appKitText)
        #else
        result.uiKit.font = font
        result.uiKit.foregroundColor = .label
        #endif
        return result
    }

    private func searchBar(for content: LoadedFileContent) -> some View {
        HStack {
            TextField("Find in Document", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
            Text(matchCount(in: content).formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
            Button("Close", systemImage: "xmark") {
                isShowingSearch = false
                searchQuery = ""
            }
            .labelStyle(.iconOnly)
        }
        .padding(8)
    }

    private func matchCount(in content: LoadedFileContent) -> Int {
        // Counted over the presented text, which is what the reader is looking at: Markdown's
        // source and its rendering do not hold the same characters.
        guard let presented else { return 0 }
        return DocumentSearch()
            .ranges(of: searchQuery, in: String(presented.text.characters))
            .count
    }

    /// Applied directly to the attributed string. Round-tripping through `NSAttributedString`
    /// would drop the SwiftUI fonts that carry Markdown's heading sizes.
    private func highlighted(_ attributedText: AttributedString) -> AttributedString {
        guard !searchQuery.isEmpty else { return attributedText }
        var result = attributedText
        let text = String(result.characters)
        for nsRange in DocumentSearch().ranges(of: searchQuery, in: text) {
            guard let stringRange = Range(nsRange, in: text),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: result),
                  let upper = AttributedString.Index(stringRange.upperBound, within: result) else {
                continue
            }
            // The platform attribute, for the same reason the fonts are: SwiftUI's does not
            // survive the crossing into `NSAttributedString`, so the marks simply vanished.
            #if os(macOS)
            result[lower..<upper].appKit.backgroundColor = searchHighlightColor
            #else
            result[lower..<upper].uiKit.backgroundColor = searchHighlightColor
            #endif
        }
        return result
    }

    private enum ContentState {
        case loading
        case loaded(LoadedFileContent)
        case failed(String)
    }
}

/// A PDF as PDFKit draws it. The document brings its own scrolling, magnification, and page
/// handling, which is the reason PDFKit is used rather than a page rendered into an image: none of
/// that has to be rebuilt, and none of it writes to the file.
private struct ReadOnlyPDFView: View {
    let data: Data
    @Binding var zoomCommand: PDFZoomCommand?

    var body: some View {
        if let document = PDFDocument(data: data) {
            PlatformPDFView(document: document, zoomCommand: $zoomCommand)
        } else {
            ContentUnavailableView(
                "Document Could Not Be Read",
                systemImage: "exclamationmark.triangle",
                description: Text("This PDF could not be opened.")
            )
        }
    }
}

#if os(macOS)
private struct PlatformPDFView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var zoomCommand: PDFZoomCommand?

    func makeNSView(context: Context) -> PDFView {
        makeConfiguredPDFView()
    }

    func updateNSView(_ view: PDFView, context: Context) {
        updatePDFView(view, with: document)
    }
}
#else
private struct PlatformPDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var zoomCommand: PDFZoomCommand?

    func makeUIView(context: Context) -> PDFView {
        makeConfiguredPDFView()
    }

    func updateUIView(_ view: PDFView, context: Context) {
        updatePDFView(view, with: document)
    }
}
#endif

private extension PlatformPDFView {
    /// One continuous vertical column of pages. Fit Page and Fit Width change only magnification
    /// and position; neither changes the document's reading model.
    func makeConfiguredPDFView() -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        #if !os(macOS)
        // A page controller replaces the vertical column with sideways page navigation.
        view.usePageViewController(false)
        #endif
        return view
    }

    /// Assigned only when it is a different document. Setting the same one again returns the reader
    /// to the first page and drops the magnification they chose.
    func updatePDFView(_ view: PDFView, with document: PDFDocument) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
            // A continuous PDF view auto-scales to its width. Once its first layout has supplied
            // a usable pane size, state the reader's initial choice explicitly so a short or
            // narrow first page is centred on every axis with spare room.
            DispatchQueue.main.async {
                guard view.document === document else { return }
                #if os(macOS)
                view.layoutSubtreeIfNeeded()
                #else
                view.layoutIfNeeded()
                #endif
                self.apply(.fitPage, to: view)
            }
        }
        guard let zoomCommand else { return }
        apply(zoomCommand, to: view)
        // After this update, not during it: clearing the binding here would change state SwiftUI is
        // in the middle of reading.
        DispatchQueue.main.async { self.zoomCommand = nil }
    }

    /// Change the magnification without changing the continuous vertical reading model.
    ///
    /// The reading position is read off the pane before the scale changes, because afterwards the
    /// pane is somewhere else entirely — that is the whole reason this second step exists.
    func apply(_ command: PDFZoomCommand, to view: PDFView) {
        guard let page = view.currentPage ?? view.document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: view.displayBox)
        let scaleFactor = command.scaleFactor(
            pageSize: pageBounds.size,
            rotation: page.rotation,
            available: view.bounds.size
        )
        guard let scaleFactor else { return }
        let visibleTopInPage = view.convert(CGPoint(x: 0, y: 0), to: page).y

        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = false
        layoutPDFView(view)
        view.scaleFactor = scaleFactor
        view.go(
            to: command.destinationRect(
                pageBounds: pageBounds,
                visibleTopInPage: visibleTopInPage,
                paneHeight: view.bounds.height,
                scaleFactor: scaleFactor
            ),
            on: page
        )
        layoutPDFView(view)
        centerContinuousPageHorizontally(page, pageBounds: pageBounds, in: view)
    }

    private func layoutPDFView(_ view: PDFView) {
        #if os(macOS)
        view.layoutSubtreeIfNeeded()
        #else
        view.layoutIfNeeded()
        #endif
    }

    /// PDFKit's public navigation APIs cannot set the horizontal position of one page in a
    /// continuous column whose pages have different widths. They preserve the column's previous
    /// offset, so a page just shown alone can return right-shifted. Until PDFKit exposes that
    /// position, correct only the private scroll container's x offset after Fit Width; retain
    /// this isolation so it can be deleted when a public API becomes available. Never alter y:
    /// it is the reader's preserved vertical position.
    func centerContinuousPageHorizontally(
        _ page: PDFPage,
        pageBounds: CGRect,
        in view: PDFView
    ) {
        let pageRect = view.convert(pageBounds, from: page)
        centerContinuousPageHorizontally(
            pageMidX: pageRect.midX,
            paneMidX: view.bounds.midX,
            in: view
        )
    }

    #if os(macOS)
    private func centerContinuousPageHorizontally(
        pageMidX: CGFloat,
        paneMidX: CGFloat,
        in view: PDFView
    ) {
        guard let scrollView = firstScrollView(in: view),
              let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let minimumOffset = documentView.bounds.minX
        let maximumOffset = max(minimumOffset, documentView.bounds.maxX - clipView.bounds.width)
        guard let corrected = PDFZoomCommand.correctedHorizontalOffset(
            currentOffset: currentOrigin.x,
            pageMidX: pageMidX,
            paneMidX: paneMidX,
            minimumOffset: minimumOffset,
            maximumOffset: maximumOffset
        ) else { return }
        clipView.scroll(to: CGPoint(x: corrected, y: currentOrigin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) { return scrollView }
        }
        return nil
    }
    #else
    private func centerContinuousPageHorizontally(
        pageMidX: CGFloat,
        paneMidX: CGFloat,
        in view: PDFView
    ) {
        guard let scrollView = firstScrollView(in: view) else { return }
        let minimumOffset = -scrollView.adjustedContentInset.left
        let maximumOffset = max(
            minimumOffset,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        guard let corrected = PDFZoomCommand.correctedHorizontalOffset(
            currentOffset: scrollView.contentOffset.x,
            pageMidX: pageMidX,
            paneMidX: paneMidX,
            minimumOffset: minimumOffset,
            maximumOffset: maximumOffset
        ) else { return }
        scrollView.setContentOffset(
            CGPoint(x: corrected, y: scrollView.contentOffset.y),
            animated: false
        )
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) { return scrollView }
        }
        return nil
    }
    #endif
}

private struct ReadOnlyVideoView: View {
    let video: LoadedVideoContent
    @State private var player: AVPlayer?
    @State private var failureMessage: String?

    var body: some View {
        Group {
            if let player {
                PlatformVideoPlayer(player: player)
            } else if let failureMessage {
                ContentUnavailableView(
                    "Video Could Not Be Played",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failureMessage)
                )
            } else {
                ProgressView("Loading…")
            }
        }
        .task(id: video.url) {
            player?.pause()
            player = nil
            failureMessage = nil
            do {
                let asset = AVURLAsset(url: video.url)
                guard try await asset.load(.isPlayable) else {
                    failureMessage = String(localized: "This video cannot be played on this device.")
                    return
                }
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch {
                failureMessage = error.localizedDescription
            }
        }
        .onDisappear {
            player?.pause()
            try? FileManager.default.removeItem(at: video.url)
        }
    }
}

#if os(macOS)
/// SwiftUI's macOS VideoPlayer currently aborts while constructing its internal representable on
/// the tested macOS 26.6.1 runtime. AVPlayerView is the same system AVKit player without that extra
/// bridge, and gives the Mac its standard transport controls.
private struct PlatformVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        // Pinch to magnify the picture, and two fingers to move around inside it once it no longer
        // fits — AVPlayerView declines the gesture until asked, exactly as WKWebView does, and its
        // header says the behaviour matches NSScrollView. AVKit owns the gesture, the bounds, and
        // the limits; the Mac only stops refusing it. The transport controls float above and keep
        // their own size, which is why this is the player's own magnification rather than the
        // whole view scaled inside a scroll view.
        view.allowsMagnification = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
#else
/// The system player, on a scroll view that lets the reader pinch in and move around inside the
/// picture.
///
/// The Mac gets this from AVKit itself — `AVPlayerView.allowsMagnification`. iOS has no such
/// property: `AVPlayerViewController` offers `videoGravity`, and the system's own pinch, available
/// only full screen, merely switches between fitting and filling. Arbitrary magnification is the
/// stated requirement, so the controller's view is carried by a scroll view here. `AVPlayerViewController`
/// still owns the video and every transport control; the scroll view only scales what it drew.
private struct PlatformVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> ZoomingVideoViewController {
        ZoomingVideoViewController(player: player)
    }

    func updateUIViewController(_ controller: ZoomingVideoViewController, context: Context) {
        controller.setPlayer(player)
    }
}

final class ZoomingVideoViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let playerController = AVPlayerViewController()
    private var lastBoundsSize: CGSize = .zero
    private var videoBoundsObservation: NSKeyValueObservation?

    init(player: AVPlayer) {
        super.init(nibName: nil, bundle: nil)
        playerController.player = player
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setPlayer(_ player: AVPlayer) {
        guard playerController.player !== player else { return }
        playerController.player = player
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self
        // Matching the picture viewer: nothing drifts past the video's own edge, and a video at
        // its fitted size does not move at all.
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1
        // The same ceiling the pictures use, measured from the fitted size, which for a video
        // laid into the pane is 1.
        scrollView.maximumZoomScale = ImageZoomCommand.maximumScale(fittingScale: 1)
        view.addSubview(scrollView)

        addChild(playerController)
        scrollView.addSubview(playerController.view)
        playerController.didMove(toParent: self)

        // Where the picture sits inside the player is known only once the video is ready, and it
        // changes with the movie's own shape.
        videoBoundsObservation = playerController.observe(\.videoBounds, options: [.new]) {
            [weak self] _, _ in
            MainActor.assumeIsolated { self?.limitScrollingToTheVideo() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        scrollView.frame = view.bounds
        guard view.bounds.size != lastBoundsSize else { return }
        lastBoundsSize = view.bounds.size
        // A rotation or a pane resized under the reader changes what "the whole video" means, so
        // the zoom starts over rather than keeping a scale measured against the old size.
        scrollView.zoomScale = 1
        playerController.view.frame = CGRect(origin: .zero, size: view.bounds.size)
        scrollView.contentSize = view.bounds.size
        updateControlsVisibility()
        limitScrollingToTheVideo()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { playerController.view }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateControlsVisibility()
        limitScrollingToTheVideo()
    }

    /// A movie rarely has the pane's shape, so the player draws it with black either side of it.
    /// Zooming the player zooms those bands too, and without this the reader can drag until only
    /// black is left. Negative insets take the bands back out of what can be reached, which is the
    /// picture viewer's rule — panning stops at the picture's own edge.
    private func limitScrollingToTheVideo() {
        let video = playerController.videoBounds
        let full = playerController.view.bounds
        guard video.width > 0, video.height > 0, full.width > 0, full.height > 0 else {
            scrollView.contentInset = .zero
            return
        }
        // Only on the axis the picture has outgrown. While it still fits, the bands are what
        // holds it in the middle of the pane, and taking them out of reach pins it to a corner.
        let scale = scrollView.zoomScale
        let isWider = video.width * scale > scrollView.bounds.width
        let isTaller = video.height * scale > scrollView.bounds.height
        scrollView.contentInset = UIEdgeInsets(
            top: isTaller ? -video.minY * scale : 0,
            left: isWider ? -video.minX * scale : 0,
            bottom: isTaller ? -(full.maxY - video.maxY) * scale : 0,
            right: isWider ? -(full.maxX - video.maxX) * scale : 0
        )
    }

    /// The transport controls are laid out to the controller's own bounds, so zooming carries them
    /// off the screen and enlarges what is left of them. Enlarged is a state for looking at the
    /// picture; the controls come back with the fitted size, at the size the system drew them.
    private func updateControlsVisibility() {
        let isFitted = scrollView.zoomScale <= scrollView.minimumZoomScale + imageZoomEpsilon
        guard playerController.showsPlaybackControls != isFitted else { return }
        playerController.showsPlaybackControls = isFitted
    }
}
#endif

#if os(macOS)
private let searchHighlightColor = NSColor.systemYellow.withAlphaComponent(0.55)
#else
private let searchHighlightColor = UIColor.systemYellow.withAlphaComponent(0.55)
#endif
