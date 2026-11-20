#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A row that is only a way further in: a place this list can open, rather than something in the
/// archive.
///
/// Two rows need this. A step of the tag tree is not an item — `Dev` exists because `Dev/Xcode`
/// does — and Unsorted is not one either: it is the files nobody filed, and no record stands for
/// it. Both read as a folder does and open as a folder does, and neither can be chosen, renamed,
/// or dragged.
struct ArchivePlaceRow: Hashable, Identifiable {
    let id: String
    let name: String
    let symbolName: String
}

/// One row of a Mac list: something in the archive, or a place that leads further in.
///
/// A place row exists because every area now shows one level at a time — the folders under this
/// folder and the files in it, the tags under this tag and the files given its name. Only the
/// folders' half of that had rows to open, because a folder is an item and a step of a tag's path
/// is not; rather than making one out of it, the list is told it may also carry a row that is only
/// a way further in.
enum ArchiveTableRow: Hashable {
    case item(ArchiveItem)
    case place(ArchivePlaceRow)

    /// What the row is showing, rather than which row it is. The table redraws when this changes.
    var rowContents: String {
        switch self {
        case .item(let item): return item.rowContents
        case .place(let place): return "place:\(place.id):\(place.name)"
        }
    }
}

/// A list of the archive's items, as the Mac makes one.
///
/// AppKit's table rather than SwiftUI's list, because renaming in place is what a Mac list already
/// does and SwiftUI's will not let it happen: the list takes clicks and keys before a field inside a
/// row ever sees them, so a second click on a chosen row never arrives and Escape never cancels.
/// Here the row's own text field is editable, and the behaviour — click what is already selected to
/// edit it, Return to keep, Escape to put it back — comes with the control.
struct ArchiveItemTable: NSViewRepresentable {
    let items: [ArchiveItem]
    /// The places directly under the one being shown — the steps of the tag tree under this tag,
    /// or Unsorted at the top of the archive — listed above the files the way a folder's own
    /// folders are listed above its files. They are a way further in and nothing else: a place is
    /// not an item, so it cannot be chosen, renamed here, or dragged.
    var placeRows: [ArchivePlaceRow] = []
    let viewModel: ArchiveViewModel
    /// Everything chosen, in the order the list shows it. A set rather than one id because the
    /// table lets the reader choose several — the whole point of Command-click and Command-A — and
    /// every command here acts on all of them.
    @Binding var selection: Set<UUID>
    /// The new name for a file, already trimmed by the caller's own rules. Absent where names
    /// cannot be changed at all, as in the Trash.
    var onRename: ((ArchiveFile, String) -> Void)?
    /// Files dropped in from outside the app.
    var onImport: ([URL]) -> Void = { _ in }
    /// What the row offers on a right-click, built where the rest of the archive's commands live.
    let commands: (ArchiveItem, NSTableView, Int) -> NSMenu
    /// What else the row has to say, shown after the name: what comes back with a folder in the
    /// Trash, which the row otherwise gave no sign of.
    var detail: (ArchiveItem) -> String? = { _ in nil }
    /// Opening a row, as a double click does in the Finder. Only folders answer to it; a file is
    /// already shown beside the list by choosing it.
    var onOpen: ((ArchiveItem) -> Void)?
    /// Going one step further in, which is what a place row is for.
    var onOpenPlace: ((ArchivePlaceRow) -> Void)?

    /// The rows in the order the table draws them.
    var rows: [ArchiveTableRow] {
        placeRows.map(ArchiveTableRow.place) + items.map(ArchiveTableRow.item)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = PressedRowTableView()
        table.onPress = { [coordinator = context.coordinator] row in coordinator.notePress(row) }
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 32
        // The row is as tall as what it has to say: a name that wraps, and marks that wrap under
        // it. Left to the table rather than measured here — the cell's own constraints already
        // describe the height, and a second measurement is a second answer to keep in step.
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openClickedRow)
        // The one column is the width of the list. It was left to itself while every label sized
        // itself to its own text; now that a row wraps its text, the width it wraps at has to be
        // the width the reader sees.
        let column = NSTableColumn(identifier: Coordinator.column)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.autoresizingMask = .width
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.registerForDraggedTypes([.fileURL, .URL])
        table.menu = NSMenu()
        table.menu?.delegate = context.coordinator
        context.coordinator.table = table
        table.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.tableWidthChanged),
            name: NSView.frameDidChangeNotification,
            object: table
        )

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = scrollView.documentView as? NSTableView else { return }
        let shown = rows
        if coordinator.shownRows.map(\.rowContents) != shown.map(\.rowContents) {
            coordinator.shownRows = shown
            table.reloadData()
        } else {
            coordinator.shownRows = shown
        }
        let chosen = IndexSet(shown.indices.filter { index in
            guard case .item(let item) = shown[index] else { return false }
            return selection.contains(item.id)
        })
        coordinator.whileApplyingSelection {
            if table.selectedRowIndexes != chosen {
                table.selectRowIndexes(chosen, byExtendingSelection: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        static let column = NSUserInterfaceItemIdentifier("name")
        var parent: ArchiveItemTable
        var shownRows: [ArchiveTableRow] = []
        weak var table: NSTableView?
        /// True while the selection is being pushed in from outside, so it is not reported back.
        private var isApplyingSelection = false
        /// The width the rows were last built for, so a resize that does not change it does nothing.
        private var widthWhenDrawn: CGFloat?

        func whileApplyingSelection(_ apply: () -> Void) {
            isApplyingSelection = true
            apply()
            isApplyingSelection = false
        }

        init(_ parent: ArchiveItemTable) {
            self.parent = parent
            shownRows = parent.rows
        }

        /// The archive item on a row, where the row is one. A place row is not an item, and every
        /// command here — renaming, dragging, the menu, the pane beside the list — is about items.
        private func item(at row: Int) -> ArchiveItem? {
            guard shownRows.indices.contains(row), case .item(let item) = shownRows[row] else {
                return nil
            }
            return item
        }

        /// A file was pressed, which is not the same as a file becoming the selection. Pressing the
        /// row already chosen changes no selection at all, and that press is exactly how a second
        /// look at a bookmark's page is asked for; a file merely restored at launch is never
        /// pressed, so it still opens nothing.
        ///
        /// Noted before the press reaches the table, so the choice is already recorded by the time
        /// the new selection reaches the pane beside the list and that pane goes looking for one.
        func notePress(_ row: Int) {
            guard case .file(let file)? = item(at: row) else { return }
            parent.viewModel.noteFileChosen(file.id)
        }

        @objc func openClickedRow() {
            guard let table, shownRows.indices.contains(table.clickedRow) else { return }
            switch shownRows[table.clickedRow] {
            case .item(let item): parent.onOpen?(item)
            case .place(let place): parent.onOpenPlace?(place)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { shownRows.count }

        /// A place row is a way further in, not something to act on, so it never becomes the
        /// selection — the commands beside this list all read the selection as archive items.
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            item(at: row) != nil
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard shownRows.indices.contains(row) else { return nil }
            let cell = tableView.makeView(withIdentifier: Self.column, owner: self) as? ItemCellView
                ?? ItemCellView(identifier: Self.column, delegate: self)
            switch shownRows[row] {
            case .item(let item):
                let detail = parent.detail(item)
                cell.show(
                    item,
                    detail: detail,
                    isRenameable: parent.onRename != nil,
                    viewModel: parent.viewModel,
                    marksWidth: ItemCellView.marksWidth(in: tableView, besideDetail: detail)
                )
            case .place(let place):
                cell.show(place)
            }
            return cell
        }

        /// The width a mark has to fit changes with the window, and it is settled before the row is
        /// measured rather than after, so the row's height is the height of what it ends up saying.
        @objc func tableWidthChanged() {
            guard let table, table.tableColumns.first?.width != widthWhenDrawn else { return }
            widthWhenDrawn = table.tableColumns.first?.width
            let rows = table.rows(in: table.visibleRect)
            guard rows.length > 0 else { return }
            let visible = IndexSet(integersIn: rows.location..<(rows.location + rows.length))
            table.noteHeightOfRows(withIndexesChanged: visible)
            table.reloadData(forRowIndexes: visible, columnIndexes: IndexSet(integer: 0))
        }

        /// Nothing chosen is worth saying too. Left unsaid, clicking the empty space below the rows
        /// took the highlight off the row while the window went on holding it: a command acting on
        /// the selection stayed available, and pressing it brought the row back and asked about
        /// something the reader had just let go of.
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let table else { return }
            parent.selection = Set(
                table.selectedRowIndexes.compactMap { item(at: $0)?.id }
            )
        }

        // MARK: Renaming

        /// Ending the edit keeps the name. Escape never reaches here: the control puts the old name
        /// back itself and reports no change, which is exactly what cancelling should do.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let file = file(for: field) else {
                return
            }
            let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = withoutExtension(entered, of: file)
            guard let onRename = parent.onRename, !name.isEmpty, name != file.displayName else {
                field.stringValue = file.sidebarDisplayName
                return
            }
            onRename(file, name)
        }

        /// A typed extension is dropped rather than kept: it is already the file's, and keeping it
        /// would leave the name reading twice.
        private func withoutExtension(_ entered: String, of file: ArchiveFile) -> String {
            guard let extensionName = file.originalExtension, !extensionName.isEmpty else {
                return entered
            }
            let suffix = ".\(extensionName)"
            guard entered.count > suffix.count,
                  entered.lowercased().hasSuffix(suffix.lowercased()) else {
                return entered
            }
            return String(entered.dropLast(suffix.count))
        }

        private func file(for field: NSTextField) -> ArchiveFile? {
            guard let table else { return nil }
            guard case .file(let file)? = item(at: table.row(for: field)) else { return nil }
            return file
        }

        // MARK: Dragging

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            guard let item = item(at: row) else { return nil }
            let dragged = NSPasteboardItem()
            dragged.setString(item.id.uuidString, forType: .string)
            return dragged
        }

        /// Dragging one of several chosen rows takes them all, as it does in the Finder. Dragging a
        /// row that is not chosen takes that row alone, and the table makes it the selection first.
        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            guard !rowIndexes.isSubset(of: tableView.selectedRowIndexes) else { return }
            tableView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
        }

        /// Files from outside land in the folder being shown, wherever in the list they are let go:
        /// this list has no order of its own for a drop to mean anything else.
        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard info.draggingSource == nil,
                  info.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) else { return [] }
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: nil
            ) as? [URL] ?? []
            guard !urls.isEmpty else { return false }
            parent.onImport(urls)
            return true
        }

        // MARK: Commands

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, case let row = table.clickedRow, let clicked = item(at: row) else {
                return
            }
            // Right-clicking a row that is not among those chosen makes it the choice, as it does
            // in the Finder; right-clicking one that is leaves the rest chosen, and the commands
            // act on all of them.
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes([row], byExtendingSelection: false)
            }
            for item in parent.commands(clicked, table, row).items {
                menu.addItem(item.copy() as! NSMenuItem)
            }
        }

        /// Begins editing a row's name, which is what the Rename command asks for.
        func beginEditing(row: Int) {
            guard let table, item(at: row) != nil else { return }
            table.editColumn(0, row: row, with: nil, select: false)
        }
    }
}

/// A table that says which row a press landed on, before the press decides what is chosen.
///
/// The selection cannot carry this on its own. Pressing the row that is already chosen leaves the
/// selection exactly as it was, so nothing changes for anyone to notice — and that press is how the
/// reader asks to see a bookmark's page again.
///
/// A press that hands a row's name to the field editor never arrives here: the table lets it
/// through to the text field, and a second press on a chosen row's name is how a Mac list is asked
/// for a rename rather than for the row.
private final class PressedRowTableView: NSTableView {
    var onPress: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let pressed = row(at: convert(event.locationInWindow, from: nil))
        if pressed >= 0 { onPress?(pressed) }
        super.mouseDown(with: event)
    }
}

/// A name that starts out selected by the part that is the user's, as the Finder does: the extension
/// stays in view but outside the selection, so typing replaces the name and leaves the kind alone.
///
/// The cell is where this belongs. Reaching for the field editor once editing has begun races the
/// control's own select-all and loses.
private final class FileNameCell: NSTextFieldCell {
    /// How much of the name is the user's to replace.
    var editableLength: Int?

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        let length = editableLength.map { min($0, (stringValue as NSString).length) } ?? selLength
        super.select(
            withFrame: rect,
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: 0,
            length: length
        )
    }
}

/// A menu item that runs what it was given. AppKit's own takes a target and a selector, which for a
/// menu built from a handful of closures means a class per command.
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(ActionMenuItem.runAction), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    /// AppKit copies a menu item before showing it — and copies a whole submenu with the item it
    /// hangs from. The copy is made by calling the class's own `init(title:action:keyEquivalent:)`,
    /// which on this subclass reached an initializer that had nothing to run and trapped: opening
    /// the file menu, once it had a submenu in it, crashed the app. Copying is answered here
    /// instead, and the closure comes with it.
    override func copy(with zone: NSZone? = nil) -> Any {
        ActionMenuItem(title: title, isEnabled: isEnabled, action: run)
    }

    /// Never called by us. Present so that anything reaching for `NSMenuItem`'s designated
    /// initializer finds something whole rather than a trap.
    override init(title: String, action: Selector?, keyEquivalent: String) {
        run = {}
        super.init(title: title, action: action, keyEquivalent: keyEquivalent)
    }

    @objc fileprivate func runAction() { run() }
}

/// A row: the item's picture, its name ready to be edited, and whatever else it has to say.
fileprivate extension ArchiveItem {
    /// What the row is showing, rather than which item it is.
    ///
    /// The table redraws when this changes. Comparing ids alone missed a file that had just been
    /// given a tag: the same file, in the same place, now with a line under its name to draw.
    var rowContents: String {
        switch self {
        case .folder(let folder): return "folder:\(folder.id)"
        case .file(let file):
            let tags = file.tagIDs.map(\.uuidString).sorted().joined(separator: ",")
            return "file:\(file.id):\(file.parentFolderID?.uuidString ?? "root"):\(file.isFavorite):\(tags)"
        }
    }
}

private final class ItemCellView: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private var nameCell: FileNameCell? { name.cell as? FileNameCell }
    private let detail = NSTextField(labelWithString: "")
    private let tags = NSTextField(labelWithString: "")
    private let picture = NSImageView()
    /// Held so the name can sit on its own in a row of one line, and give the bottom of the row to
    /// the tags when there are any.
    private var nameAlone: NSLayoutConstraint!
    private var tagsUnderName: NSLayoutConstraint!
    /// What the second line says, kept so it can be drawn again when the row's colour changes.
    private var subtitle: [ArchiveRowMark]?
    /// What one line of marks holds, which decides which of them have to be shortened.
    private var marksWidth: CGFloat = 0
    private var thumbnailTask: Task<Void, Never>?
    private var shownItemID: UUID?

    init(identifier: NSUserInterfaceItemIdentifier, delegate: NSTextFieldDelegate) {
        super.init(frame: .zero)
        self.identifier = identifier

        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 4
        picture.layer?.masksToBounds = true
        picture.translatesAutoresizingMaskIntoConstraints = false

        name.cell = FileNameCell(textCell: "")
        name.isEditable = true
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        // As the policy asks: taken from the middle so the extension is left standing, which
        // AppKit will only do on one line, or wrapped as far as the policy allows and shortened
        // off the end.
        let policy = ArchiveRowTextPolicy.current
        name.usesSingleLineMode = false
        name.maximumNumberOfLines = policy.nameShortening == .middle ? 1 : policy.nameLines
        name.lineBreakMode = policy.nameShortening == .middle ? .byTruncatingMiddle : .byWordWrapping
        name.cell?.truncatesLastVisibleLine = true
        name.delegate = delegate
        name.font = .preferredFont(forTextStyle: .body)
        name.translatesAutoresizingMaskIntoConstraints = false
        // The row is as wide as the list, not as wide as the longest name in it: a name that will
        // not fit gives way and is shortened, rather than pushing the row out past the pane.
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detail.font = .preferredFont(forTextStyle: .body)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The detail is exactly as wide as what it says, and the name and the marks divide what is
        // left. Without this the row has two labels that both give way, and how it splits between
        // them is anyone's guess.
        detail.setContentHuggingPriority(.required, for: .horizontal)
        detail.translatesAutoresizingMaskIntoConstraints = false

        tags.font = .preferredFont(forTextStyle: .caption1)
        tags.textColor = .secondaryLabelColor
        // Wrapping to the lines the policy allows, and an ellipsis at the end of the last of them:
        // a mark left out without a sign is a file that looks as though it has fewer tags.
        tags.usesSingleLineMode = false
        tags.maximumNumberOfLines = policy.metadataLines ?? 0
        tags.cell?.truncatesLastVisibleLine = true
        tags.lineBreakMode = .byTruncatingTail
        tags.translatesAutoresizingMaskIntoConstraints = false
        tags.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tags.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(picture)
        addSubview(name)
        addSubview(tags)
        addSubview(detail)
        textField = name
        imageView = picture

        // Widths are settled rather than merely bounded, because text that wraps needs to know how
        // wide it may be before it can say how tall it is, and the row's height is now the answer
        // to that question.
        NSLayoutConstraint.activate([
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.centerYAnchor.constraint(equalTo: centerYAnchor),
            picture.widthAnchor.constraint(equalToConstant: 28),
            picture.heightAnchor.constraint(equalToConstant: 28),
            name.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: detail.leadingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            tags.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            tags.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            tags.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // A count of lines is not by itself a limit: AppKit's label grows to whatever it has to
        // say, and only stops at the line it cannot fit. Told how tall that many lines are, it
        // stops there and ends the last one in an ellipsis.
        if let lines = policy.metadataLines {
            tags.heightAnchor.constraint(
                lessThanOrEqualToConstant: Self.height(ofLines: lines, in: .preferredFont(forTextStyle: .caption1))
            ).isActive = true
        }

        nameAlone = name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding)
        tagsUnderName = tags.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding)
        nameAlone.isActive = true
    }

    /// Measured from a mark rather than from the font: a line carrying a symbol is taller than a
    /// line of plain text, and it is marks that these lines hold.
    private static func height(ofLines lines: Int, in font: NSFont) -> CGFloat {
        let oneLine = ArchiveRowText.line(
            [ArchiveRowMark(symbol: "tag", text: "X")],
            font: font,
            colour: .labelColor
        ).size().height
        // With room to spare, because a line laid out among others is a little taller than a line
        // measured on its own. Less than a whole line of slack, so the line after the last allowed
        // one still has nowhere to go: what AppKit cannot fit whole, it truncates.
        return oneLine * (CGFloat(lines) + 0.4)
    }

    /// Above the name and below whatever the row ends with. Two lines of text and this above and
    /// below them come to the height the rows had when it was fixed.
    private static let padding: CGFloat = 8

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The row's second colour follows the row's own.
    ///
    /// The name is AppKit's to look after — it is the cell's `textField` — but the second line and
    /// the detail are ours, and dimmed grey on a highlighted row reads as unavailable rather than
    /// secondary. The symbols are drawn in that colour too, so they are redrawn here.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            detail.textColor = secondaryColor
            drawSubtitle()
        }
    }

    private var secondaryColor: NSColor {
        backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.85)
            : .secondaryLabelColor
    }

    /// Where a file sits, whether it is a favourite, and what it is about — under its name, the
    /// way a bookmark shelf lists them. A folder is the place itself and has none of this to say.
    ///
    /// What the marks are and in what order is decided in `ArchiveRowText`, which the phone's rows
    /// read from too.
    private func showTags(on item: ArchiveItem, viewModel: ArchiveViewModel) {
        guard case .file(let file) = item else {
            subtitle = nil
            tags.isHidden = true
            tagsUnderName.isActive = false
            nameAlone.isActive = true
            return
        }
        subtitle = ArchiveRowText.marks(on: file, viewModel: viewModel)
        drawSubtitle()
        tags.isHidden = false
        nameAlone.isActive = false
        tagsUnderName.isActive = true
    }

    private func drawSubtitle() {
        guard let subtitle else { return }
        tags.attributedStringValue = ArchiveRowText.line(
            subtitle,
            font: .preferredFont(forTextStyle: .caption1),
            colour: secondaryColor,
            fittingWidth: marksWidth
        )
    }

    /// What is left for the marks once the row's own furniture has taken its share: the thumbnail
    /// and the gap after it at one end, whatever the row says on the right at the other, and the
    /// list's own inset around all of it. Worked out from the column rather than measured from a
    /// laid-out row, because the marks have to be settled before the row can be measured at all.
    static func marksWidth(in table: NSTableView, besideDetail detail: String?) -> CGFloat {
        let column = table.tableColumns.first?.width ?? table.bounds.width
        let detailWidth = detail.map {
            NSAttributedString(
                string: $0,
                attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
            ).size().width + 8
        } ?? 0
        // A little under rather than a little over: shortening a mark that would have fitted costs
        // a character, and leaving one that does not costs the rule.
        return max(40, column - Self.listInset - 28 - 8 - detailWidth - 2)
    }

    /// The inset the list's own style keeps around a row, which the column width still counts.
    private static let listInset: CGFloat = 32

    /// A place: its name, and nothing under it. The row carries no marks and no number — it is the
    /// same kind of row a folder gets here, and a folder's row in this list carries neither either.
    func show(_ place: ArchivePlaceRow) {
        detail.stringValue = ""
        detail.isHidden = true
        subtitle = nil
        tags.isHidden = true
        tagsUnderName.isActive = false
        nameAlone.isActive = true
        name.stringValue = place.name
        name.isEditable = false
        nameCell?.editableLength = nil
        picture.image = NSImage(systemSymbolName: place.symbolName, accessibilityDescription: nil)
        thumbnailTask?.cancel()
        shownItemID = nil
    }

    func show(
        _ item: ArchiveItem,
        detail detailText: String?,
        isRenameable: Bool,
        viewModel: ArchiveViewModel,
        marksWidth: CGFloat
    ) {
        detail.stringValue = detailText ?? ""
        detail.isHidden = detailText == nil
        self.marksWidth = marksWidth
        showTags(on: item, viewModel: viewModel)

        switch item {
        case .folder(let folder):
            name.stringValue = folder.name
            name.isEditable = false
            nameCell?.editableLength = nil
            picture.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            thumbnailTask?.cancel()
            shownItemID = folder.id
        case .file(let file):
            name.stringValue = file.sidebarDisplayName
            name.isEditable = isRenameable
            nameCell?.editableLength = (file.displayName as NSString).length
            picture.image = NSImage(
                systemSymbolName: file.effectiveDisplayFormat.systemImage,
                accessibilityDescription: nil
            )
            guard shownItemID != file.id else { return }
            shownItemID = file.id
            thumbnailTask?.cancel()
            thumbnailTask = Task { @MainActor [weak self] in
                let data = try? await viewModel.loadThumbnail(for: file)
                guard let self, shownItemID == file.id, let data,
                      let image = NSImage(data: data) else {
                    return
                }
                picture.image = image
            }
        }
    }
}
#endif
