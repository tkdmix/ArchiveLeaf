import SwiftUI

/// One thing a row says about a file besides its name: where it sits, that it is a favourite, or a
/// tag it carries.
struct ArchiveRowMark {
    let symbol: String
    let text: String
}

/// What a row says about a file besides its name, and how much of it is shown.
///
/// Built here rather than in each list, so that the Mac's rows and the phone's rows say the same
/// things in the same order and cannot drift apart. Each platform then draws the marks with its own
/// text control — one `Text`, one `NSTextField` — and both wrap and shorten the way that control
/// already does.
enum ArchiveRowText {
    /// Where the file sits, whether it is a favourite, and what it is about.
    ///
    /// The folder is named even while its own list is open, where every row would say the same
    /// thing: it is the one line that reads alike everywhere — in a folder, in Favorites, under a
    /// tag — and a line that appears and disappears with the pane is harder to read than one that
    /// is always in the same place saying the same kind of thing. It is named on its own, without
    /// the path above it: what is above it is the tree in the Folders pane.
    @MainActor
    static func marks(on file: ArchiveFile, viewModel: ArchiveViewModel) -> [ArchiveRowMark] {
        var marks = [
            ArchiveRowMark(
                // The tray the sidebar shows for Unsorted Files, so the same place is named by the
                // same symbol wherever it appears.
                symbol: file.parentFolderID == nil ? "tray" : "folder",
                text: file.parentFolderID.flatMap { viewModel.folder(id: $0)?.name }
                    ?? String(localized: "Unsorted Files")
            )
        ]
        if file.isFavorite {
            marks.append(ArchiveRowMark(symbol: "star.fill", text: ""))
        }
        marks.append(contentsOf: viewModel.tags(on: file).map { ArchiveRowMark(symbol: "tag", text: $0.name) })
        return marks
    }

    /// Two spaces, which is the only place a line may break. A mark is one line's worth or nothing:
    /// half a tag name on the line above reads as a tag of its own, so every break inside a mark is
    /// taken away and the mark is sent whole to the next line instead.
    private static let separator = "  "

    /// The mark's text with a word joiner between every character, which leaves the text as it
    /// reads and takes away every place a line could break inside it — the spaces of an English
    /// name, the slashes of an outline, and the characters of a Japanese one, which otherwise
    /// breaks anywhere at all.
    private static func unbroken(_ text: String) -> String {
        let joined = text
            .replacingOccurrences(of: " ", with: "\u{00A0}")
            .map(String.init)
            .joined(separator: "\u{2060}")
        return joined.isEmpty ? "" : "\u{00A0}" + joined
    }

    #if os(macOS)
    /// The marks as one run of text, for AppKit's table. A symbol is an image in an attachment, and
    /// an image does not follow the colour of the text around it, so the colour is given here and
    /// the line is built again when the row's own colour changes.
    ///
    /// `width` is what one line holds. A mark wider than that is the one case the joining above
    /// cannot answer — sent to a line of its own it still does not fit — so it is shortened here,
    /// from the middle, before the text control ever sees it.
    static func line(
        _ marks: [ArchiveRowMark],
        font: NSFont,
        colour: NSColor,
        fittingWidth width: CGFloat? = nil
    ) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for mark in marks {
            if line.length > 0 {
                line.append(NSAttributedString(string: separator))
            }
            let text = width.map { shortened(mark, toFit: $0, font: font, colour: colour) } ?? mark.text
            if let image = symbol(mark.symbol, colour: colour, font: font) {
                let attachment = NSTextAttachment()
                attachment.image = image
                line.append(NSAttributedString(attachment: attachment))
            }
            line.append(NSAttributedString(string: unbroken(text)))
        }
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byWordWrapping
        line.addAttributes(
            [.font: font, .foregroundColor: colour, .paragraphStyle: wrapping],
            range: NSRange(location: 0, length: line.length)
        )
        return line
    }

    /// The longest the mark's text can be and still stand on one line, ending in an ellipsis where
    /// something was taken out. The middle goes, because a tag's outline ends in the name that says
    /// most — `Dev/Xcode/iOS` is an iOS tag before it is a Dev one.
    private static func shortened(
        _ mark: ArchiveRowMark,
        toFit width: CGFloat,
        font: NSFont,
        colour: NSColor
    ) -> String {
        func fits(_ text: String) -> Bool {
            line([ArchiveRowMark(symbol: mark.symbol, text: text)], font: font, colour: colour)
                .size().width <= width
        }
        guard !fits(mark.text) else { return mark.text }

        let characters = Array(mark.text)
        // Down one character at a time from the whole name: the shortest thing that had to go is
        // the most of the name that can stay.
        for kept in stride(from: characters.count - 1, through: 1, by: -1) {
            // The end is the half that survives longest: what a name ends in is what it is.
            let head = characters.prefix(kept / 2)
            let tail = characters.suffix(kept - kept / 2)
            let candidate = String(head) + "…" + String(tail)
            if fits(candidate) {
                return candidate
            }
        }
        return "…"
    }

    private static func symbol(_ name: String, colour: NSColor, font: NSFont) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
            )
    }
    #endif
}

/// How much of a row's text is shown before it is shortened.
///
/// One spec with two sets of numbers. Give both platforms the same numbers and the rows read alike;
/// change one and only that platform moves. Nothing else in the app decides this, so a change here
/// is the whole change.
struct ArchiveRowTextPolicy {
    /// Where a name too long for the room it has gives way.
    enum NameShortening {
        /// Out of the middle, so the extension — which says what the file is — survives. AppKit
        /// shortens this way only on a single line: its text control wraps or takes from the
        /// middle, never both. So on the Mac this means one line, whatever `nameLines` says.
        case middle
        /// Off the end, once the name has wrapped as far as `nameLines` allows. The whole of the
        /// name up to there is shown, and the extension is what goes.
        case end
    }

    /// Lines the name may take, where it wraps at all.
    var nameLines: Int

    /// What a name that does not fit loses.
    var nameShortening: NameShortening

    /// Lines the marks may take, or `nil` for as many as they need. Where a limit cuts them short,
    /// the last line it allows ends in an ellipsis, so the row shows that there is more rather than
    /// quietly leaving it out.
    var metadataLines: Int?

    #if os(macOS)
    /// The Mac lists many rows in one window, and rows of an even height are what makes a long list
    /// readable at a glance.
    static let current = ArchiveRowTextPolicy(nameLines: 2, nameShortening: .middle, metadataLines: 3)
    #else
    /// The phone shows few rows at a time and is where the shelf is read closely, so the marks run
    /// to whatever length they need.
    static let current = ArchiveRowTextPolicy(nameLines: 2, nameShortening: .middle, metadataLines: nil)
    #endif
}
