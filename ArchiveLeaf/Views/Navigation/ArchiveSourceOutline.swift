#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Files eligible for a tag or Favorites drop, only when the complete dragged selection resolves
/// to files. Returning nothing instead of filtering prevents an incompatible or stale selection
/// from being applied partially.
func archiveMetadataDropFileIDs(
    requestedIDs: [UUID],
    resolvedItems: [ArchiveItem]
) -> [UUID]? {
    guard requestedIDs.count == Set(requestedIDs).count else { return nil }
    let selection = ArchiveItemSelection(
        items: resolvedItems,
        requestedIDs: Set(requestedIDs)
    )
    guard selection.canTag else { return nil }
    return selection.files.map(\.id)
}

/// The archive's structure: its folders, and the two places that gather files from across it.
///
/// AppKit's outline rather than SwiftUI's list, for the same reason the file list is AppKit's — a
/// row that can be renamed where it sits, a drop that highlights its destination, and a
/// disclosure triangle that behaves like every other one on the Mac. A folder and a file are
/// different things, but what can be done to a row should not differ by which pane it is in.
struct ArchiveSourceOutline: NSViewRepresentable {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var selection: ArchiveSource?
    let expansion: FolderExpansion

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        // Locked, not absent — as in the file list. Choosing two folders at once would have to
        // mean something to the pane beside this one before it is worth allowing.
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.indentationPerLevel = 14
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.addTableColumn(NSTableColumn(identifier: Coordinator.column))
        outline.outlineTableColumn = outline.tableColumns.first
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.registerForDraggedTypes([.string, .fileURL])
        outline.menu = NSMenu()
        outline.menu?.delegate = context.coordinator
        context.coordinator.outline = outline

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.rebuild()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuild()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
                             NSTextFieldDelegate, NSMenuDelegate {
        static let column = NSUserInterfaceItemIdentifier("source")
        var parent: ArchiveSourceOutline
        weak var outline: NSOutlineView?
        private var roots: [SourceNode] = []
        /// True while expansion is being applied from what was remembered, so the outline's own
        /// reports of opening and closing are not written straight back.
        private var isRestoringExpansion = false
        /// True while a row is selected by `applySelection()`, rather than by the reader. AppKit
        /// reports both through the same delegate callback, but only the latter may write the
        /// sidebar binding and lay a new navigation path.
        private var isApplyingSelection = false

        init(_ parent: ArchiveSourceOutline) {
            self.parent = parent
        }

        // MARK: What is listed

        func rebuild() {
            let rebuilt = SourceNode.tree(from: parent.viewModel)
            guard rebuilt != roots else {
                applySelection()
                return
            }
            roots = rebuilt
            outline?.reloadData()
            restoreExpansion()
            applySelection()
        }

        private func restoreExpansion() {
            guard let outline else { return }
            isRestoringExpansion = true
            defer { isRestoringExpansion = false }
            for node in roots.flatMap(\.selfAndDescendants) where node.isExpandable {
                if parent.expansion.isOpen(key: node.expansionKey) {
                    outline.expandItem(node)
                } else {
                    outline.collapseItem(node)
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? SourceNode)?.source != nil
        }

        private func applySelection() {
            guard let outline else { return }
            let node = roots.flatMap(\.selfAndDescendants).first {
                $0.source != nil && $0.source == parent.selection
            }
            guard let node else {
                guard outline.selectedRow != -1 else { return }
                isApplyingSelection = true
                defer { isApplyingSelection = false }
                outline.deselectAll(nil)
                return
            }
            let row = outline.row(forItem: node)
            guard row != -1, outline.selectedRow != row else { return }
            isApplyingSelection = true
            defer { isApplyingSelection = false }
            outline.selectRowIndexes([row], byExtendingSelection: false)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? SourceNode)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? SourceNode)?.children[index] ?? roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? SourceNode)?.isExpandable ?? false
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let node = item as? SourceNode else { return nil }
            let cell = outlineView.makeView(withIdentifier: Self.column, owner: self) as? SourceCellView
                ?? SourceCellView(identifier: Self.column, delegate: self)
            // No control drawn into any row. Making a folder is done where the folders are shown,
            // from the button over that pane, and from this row's own menu.
            cell.show(node)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let outline,
                  let node = outline.item(atRow: outline.selectedRow) as? SourceNode,
                  let source = node.source else {
                return
            }
            parent.selection = source
        }

        // MARK: Remembering what is open

        func outlineViewItemDidExpand(_ notification: Notification) {
            recordExpansion(from: notification, isOpen: true)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            recordExpansion(from: notification, isOpen: false)
        }

        private func recordExpansion(from notification: Notification, isOpen: Bool) {
            guard !isRestoringExpansion,
                  let node = notification.userInfo?["NSObject"] as? SourceNode else {
                return
            }
            parent.expansion.setOpen(isOpen, key: node.expansionKey)
        }

        // MARK: Renaming

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let outline,
                  case let row = outline.row(for: field),
                  let node = outline.item(atRow: row) as? SourceNode else {
                return
            }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let viewModel = parent.viewModel
            switch node.kind {
            case .folder(let folder):
                guard !name.isEmpty, name != folder.name else {
                    field.stringValue = folder.name
                    return
                }
                Task { await viewModel.renameFolder(id: folder.id, to: name) }
            case .tag(let node):
                guard let tag = node.tag else { return }
                guard !name.isEmpty, name != node.name else {
                    field.stringValue = node.name
                    return
                }
                let parentPath = tag.name.split(separator: "/").dropLast().joined(separator: "/")
                let fullName = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
                Task { await viewModel.renameTag(id: tag.id, to: fullName) }
            default:
                return
            }
        }

        // MARK: Dragging

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> NSPasteboardWriting? {
            guard let node = item as? SourceNode, case .folder(let folder) = node.kind else {
                return nil
            }
            let dragged = NSPasteboardItem()
            dragged.setString(folder.id.uuidString, forType: .string)
            return dragged
        }

        /// Onto a row means putting something in that place. A drop between rows has no meaning,
        /// because folders always appear in name order.
        /// A folder takes what is dropped on it — the file moves there. A tag does not take
        /// anything: the file stays where it is and gains the tag, which is why the drop reads as
        /// `.copy` there and `.move` on a folder.
        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard index == NSOutlineViewDropOnItemIndex else { return [] }
            guard let node = item as? SourceNode else { return [] }
            let dragged = draggedIDs(from: info)

            switch node.kind {
            case .tag(let tagNode):
                // Only from inside, and only files: a folder carries neither tags nor a star.
                guard tagNode.tag != nil,
                      info.draggingSource != nil,
                      metadataDropFileIDs(for: dragged) != nil else {
                    return []
                }
                outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
                // The file stays where it is and gains something, so this is not a move.
                return .copy
            case .favorites:
                guard info.draggingSource != nil,
                      metadataDropFileIDs(for: dragged) != nil else {
                    return []
                }
                outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .copy
            case .trash:
                guard info.draggingSource != nil,
                      dragged.contains(where: { parent.viewModel.archiveItem(id: $0) != nil }) else {
                    return []
                }
                outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
                // Out of where it was and into the Trash: the same move a folder takes.
                return .move
            default:
                break
            }

            guard node.acceptsDrops else { return [] }
            outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
            if info.draggingSource == nil { return .copy }
            guard !dragged.isEmpty, !dragged.contains(where: { $0 == node.folderID }) else {
                return []
            }
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard index == NSOutlineViewDropOnItemIndex else { return false }
            guard let node = item as? SourceNode else { return false }
            let viewModel = parent.viewModel

            switch node.kind {
            case .tag(let node):
                guard let tag = node.tag,
                      info.draggingSource != nil,
                      let fileIDs = metadataDropFileIDs(for: draggedIDs(from: info)) else {
                    return false
                }
                Task { await viewModel.setTag(tag.id, on: fileIDs, isOn: true) }
                return true
            case .favorites:
                guard info.draggingSource != nil,
                      let fileIDs = metadataDropFileIDs(for: draggedIDs(from: info)) else {
                    return false
                }
                Task { await viewModel.setFavorite(true, on: fileIDs) }
                return true
            case .trash:
                // Asked about rather than done: a folder takes everything inside it out of view,
                // and the same question is asked wherever the Trash is reached from.
                let items = draggedIDs(from: info).compactMap { viewModel.archiveItem(id: $0) }
                guard !items.isEmpty else { return false }
                viewModel.itemsPendingTrash = items
                return true
            default:
                break
            }

            guard node.acceptsDrops else { return false }
            if info.draggingSource == nil {
                let urls = info.draggingPasteboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                ) as? [URL] ?? []
                guard !urls.isEmpty else { return false }
                Task { await viewModel.inspectImports(at: urls, into: node.folderID) }
                return true
            }
            // Everything dragged, not the first of them: the list lets several be chosen and the
            // drag carries one pasteboard item per row.
            let dragged = draggedIDs(from: info)
            guard !dragged.isEmpty else { return false }
            Task {
                for id in dragged {
                    await viewModel.move(itemWithID: id, into: node.folderID)
                }
            }
            return true
        }

        private func draggedIDs(from info: NSDraggingInfo) -> [UUID] {
            (info.draggingPasteboard.pasteboardItems ?? [])
                .compactMap { $0.string(forType: .string) }
                .compactMap(UUID.init(uuidString:))
        }

        private func metadataDropFileIDs(for requestedIDs: [UUID]) -> [UUID]? {
            archiveMetadataDropFileIDs(
                requestedIDs: requestedIDs,
                resolvedItems: requestedIDs.compactMap { parent.viewModel.archiveItem(id: $0) }
            )
        }

        // MARK: Commands

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, case let row = outline.clickedRow,
                  let node = outline.item(atRow: row) as? SourceNode else {
                return
            }
            // Only where the row is one that can be chosen: a heading takes the focus ring and
            // nothing else if it is asked to select.
            if node.source != nil, outline.selectedRow != row {
                outline.selectRowIndexes([row], byExtendingSelection: false)
            }
            for item in commands(for: node, row: row) {
                menu.addItem(item)
            }
        }

        private func commands(for node: SourceNode, row: Int) -> [NSMenuItem] {
            let viewModel = parent.viewModel
            guard !viewModel.isOfflineMode else { return [] }
            switch node.kind {
            case .folders:
                return [ActionMenuItem(title: String(localized: "New Folder")) {
                    viewModel.beginCreatingFolder(in: nil)
                }]
            case .unsorted:
                // Nothing: it cannot be renamed, moved, thrown away, or given a folder inside it.
                return []
            case .folder(let folder):
                return [
                    ActionMenuItem(title: String(localized: "New Folder Inside")) {
                        viewModel.beginCreatingFolder(in: folder.id)
                    },
                    ActionMenuItem(title: String(localized: "Rename")) { [weak self] in
                        self?.outline?.editColumn(0, row: row, with: nil, select: false)
                    },
                    ActionMenuItem(title: String(localized: "Move To…")) {
                        viewModel.beginMoving([.folder(folder)])
                    },
                    .separator(),
                    ActionMenuItem(title: String(localized: "Move to Trash")) {
                        viewModel.itemsPendingTrash = [.folder(folder)]
                    },
                ]
            case .tags:
                // Nothing to make here: a tag comes into being on a file, and goes when the last
                // file lets go of it.
                return []
            case .tag(let node):
                guard let tag = node.tag else { return [] }
                return [
                    ActionMenuItem(title: String(localized: "Rename")) { [weak self] in
                        self?.outline?.editColumn(0, row: row, with: nil, select: false)
                    },
                    .separator(),
                    // Not the Trash: a tag is a name for a grouping, and there is nothing of the
                    // reader's to get back once the grouping is gone.
                    ActionMenuItem(title: String(localized: "Delete Tag")) {
                        viewModel.tagPendingDeletion = tag
                    },
                ]
            case .favorites, .trash:
                return []
            }
        }
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}

/// One row of the outline: a folder, or one of the places that are not folders.
@MainActor
final class SourceNode: NSObject {
    private struct Comparison: Hashable, Sendable {
        let identity: String
        let name: String
        let fileCount: Int
        let children: [Comparison]
    }

    enum Kind {
        /// The row the folders hang from. A heading, not a place: it holds no files of its own.
        case folders
        /// A folder in every way that matters — files sit in it, and move in and out of it — but
        /// one nobody made and nobody can move, rename, delete, or put a folder inside.
        case unsorted
        case folder(ArchiveFolder)
        case favorites
        /// The row the tags hang from. It gathers nothing itself, so it cannot be chosen.
        case tags
        case tag(TagPathNode)
        case trash
    }

    let kind: Kind
    let children: [SourceNode]
    /// How many rows this row's own list holds. Shown at the right of the row, and left off
    /// where there are none — an empty place says so by the space beside its name.
    let fileCount: Int
    /// NSObject equality is nonisolated even though the outline itself is main-actor UI. Keep the
    /// comparison independent of AppKit and of actor-isolated computed properties.
    private nonisolated let comparison: Comparison

    init(kind: Kind, children: [SourceNode] = [], fileCount: Int = 0) {
        self.kind = kind
        self.children = children
        self.fileCount = fileCount
        let identity: String
        let name: String
        switch kind {
        case .folders:
            identity = "folders"
            name = String(localized: "Folders")
        case .unsorted:
            identity = "unsorted"
            name = String(localized: "Unsorted Files")
        case .folder(let folder):
            identity = "folder:\(folder.id.uuidString)"
            name = folder.name
        case .favorites:
            identity = "favorites"
            name = String(localized: "Favorites")
        case .tags:
            identity = "tags"
            name = String(localized: "Tags")
        case .tag(let node):
            identity = node.tag.map { "tag:\($0.id.uuidString)" } ?? "tag-path:\(node.id)"
            name = node.name
        case .trash:
            identity = "trash"
            name = String(localized: "Trash")
        }
        comparison = Comparison(
            identity: identity,
            name: name,
            fileCount: fileCount,
            children: children.map(\.comparison)
        )
    }

    static func tree(from viewModel: ArchiveViewModel) -> [SourceNode] {
        [
            SourceNode(
                kind: .folders,
                // First among the folders, and staying there: every file is under some folder, and
                // the ones no one has filed are under this one.
                children: [
                    SourceNode(
                        kind: .unsorted,
                        fileCount: viewModel.itemCount(inFolderWithID: nil)
                    ),
                ] + folders(in: nil, from: viewModel)
            ),
            SourceNode(
                kind: .favorites,
                fileCount: viewModel.favoriteFiles.count
            ),
            // The heading carries no number of its own: what hangs under it are tags, and a count
            // here would be a count of a different thing than every other number in this pane.
            SourceNode(
                kind: .tags,
                children: tagNodes(TagPathNode.tree(tags: viewModel.tags, files: viewModel.files))
            ),
            SourceNode(
                kind: .trash,
                // Folders as well as files: the Trash lists both, and both come back.
                fileCount: viewModel.trashedFolders.count + viewModel.trashedFiles.count
            ),
        ]
    }

    private static func folders(in parentID: UUID?, from viewModel: ArchiveViewModel) -> [SourceNode] {
        viewModel.folders(in: parentID).map { folder in
            SourceNode(
                kind: .folder(folder),
                children: folders(in: folder.id, from: viewModel),
                fileCount: viewModel.itemCount(inFolderWithID: folder.id)
            )
        }
    }

    private static func tagNodes(_ nodes: [TagPathNode]) -> [SourceNode] {
        nodes.map { node in
            SourceNode(
                kind: .tag(node),
                children: tagNodes(node.children),
                fileCount: node.itemCount
            )
        }
    }

    /// What choosing this row shows, or nothing where the row is only a heading.
    var source: ArchiveSource? {
        switch kind {
        // Every row is a place, including the two headings: the archive's first level, and
        // everything carrying any tag. A row that shows a triangle is still somewhere to go.
        case .folders: .folders
        case .unsorted: .folder(nil)
        case .folder(let folder): .folder(folder.id)
        case .favorites: .favorites
        case .tags: .tag(path: "")
        case .tag(let node): .tag(path: node.id)
        case .trash: .trash
        }
    }

    /// The folder this row stands for, with the archive's own row standing for its root.
    var folderID: UUID? {
        if case .folder(let folder) = kind { return folder.id }
        return nil
    }

    var name: String {
        switch kind {
        case .folders: String(localized: "Folders")
        case .unsorted: String(localized: "Unsorted Files")
        case .folder(let folder): folder.name
        case .favorites: String(localized: "Favorites")
        case .tags: String(localized: "Tags")
        case .tag(let node): node.name
        case .trash: String(localized: "Trash")
        }
    }

    var symbolName: String {
        switch kind {
        case .folders: "folder"
        case .unsorted: "tray"
        case .folder: "folder"
        case .favorites: "star"
        case .tags, .tag: "tag"
        case .trash: "trash"
        }
    }

    var isRenameable: Bool {
        switch kind {
        case .folder: true
        case .tag(let node): node.tag != nil
        default: false
        }
    }

    /// What is remembered about this row being open. Folders are keyed by their id; the rows that
    /// are not folders need a key of their own, or they would share the archive's.
    var expansionKey: String {
        switch kind {
        case .tags: FolderExpansion.tagsKey
        case .tag(let node): "tag-path:\(node.id)"
        default: folderID?.uuidString ?? "root"
        }
    }

    /// Where a file can be put. The heading is not one of them — it stands for the folders, and
    /// the files that belong to no folder have their own row.
    var acceptsDrops: Bool {
        switch kind {
        case .unsorted, .folder: true
        case .folders, .favorites, .tags, .tag, .trash: false
        }
    }

    var isExpandable: Bool { !children.isEmpty }

    var selfAndDescendants: [SourceNode] { [self] + children.flatMap(\.selfAndDescendants) }

    /// Equal where the row stands for the same thing and reads the same, so that a rebuild that
    /// changed nothing leaves the outline — and what it has open — alone.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SourceNode else { return false }
        return comparison == other.comparison
    }

    override var hash: Int {
        comparison.hashValue
    }
}

/// A row: its symbol, and its name ready to be edited where that is allowed.
private final class SourceCellView: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private let symbol = NSImageView()
    private let count = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier, delegate: NSTextFieldDelegate) {
        super.init(frame: .zero)
        self.identifier = identifier

        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.contentTintColor = .controlAccentColor

        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        name.usesSingleLineMode = true
        name.cell?.truncatesLastVisibleLine = true
        name.delegate = delegate
        name.font = .preferredFont(forTextStyle: .body)
        name.translatesAutoresizingMaskIntoConstraints = false

        count.font = .preferredFont(forTextStyle: .body)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.usesSingleLineMode = true
        count.translatesAutoresizingMaskIntoConstraints = false
        // The number keeps its width and the name gives way: a folder called something long is
        // still a folder with a count, and the count is the shorter of the two to read.
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(symbol)
        addSubview(name)
        addSubview(count)
        textField = name
        imageView = symbol

        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(equalTo: trailingAnchor),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ node: SourceNode) {
        name.stringValue = node.name
        name.isEditable = node.isRenameable
        symbol.image = NSImage(systemSymbolName: node.symbolName, accessibilityDescription: nil)
        count.stringValue = node.fileCount > 0 ? node.fileCount.formatted() : ""
    }
}
#endif
