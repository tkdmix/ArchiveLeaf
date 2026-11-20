import SwiftUI

struct ArchiveFileLabel: View {
    let file: ArchiveFile
    let viewModel: ArchiveViewModel

    private let policy = ArchiveRowTextPolicy.current

    var body: some View {
        Label {
            #if os(macOS)
            name
            #else
            // Two lines, as the Mac's list has: the name, then where it sits, whether it is a
            // favourite, and what it is about.
            VStack(alignment: .leading, spacing: 2) {
                name
                secondLine
            }
            #endif
        } icon: {
            ArchiveFileThumbnail(file: file, viewModel: viewModel)
        }
        #if os(macOS)
        .labelStyle(ThumbnailLabelStyle())
        #endif
        // Named here so that a file's row can be addressed the same way wherever it is listed —
        // in a folder, in Favorites, under a tag. A row found by the words on it is a row found by
        // the current wording, in the current language.
        .accessibilityIdentifier("item-row-\(file.sidebarDisplayName)")
    }

    private var name: some View {
        Text(file.sidebarDisplayName)
            .lineLimit(policy.nameLines)
            .truncationMode(policy.nameShortening == .middle ? .middle : .tail)
    }

    #if !os(macOS)
    /// The marks wrap rather than being cut off at the edge: where the file sits and what it is
    /// about are what the row is read for, so they are shown to whatever length the policy allows.
    private var secondLine: some View {
        let marks = ArchiveRowText.marks(on: file, viewModel: viewModel)
        return MarksRow(lines: policy.metadataLines) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                HStack(spacing: 3) {
                    Image(systemName: mark.symbol)
                    if !mark.text.isEmpty {
                        Text(mark.text)
                    }
                }
                // One mark is one line's worth or nothing. A name too long for a whole line loses
                // its middle, because a tag's outline ends in the name that says most.
                .lineLimit(1)
                .truncationMode(.middle)
            }
            // Last, and only seen where a line the policy does not allow had to be left out.
            Text(verbatim: "…")
        }
        // What the policy leaves no room for is put past the edge, and the edge is where the row
        // stops drawing: a mark asked for no room at all is drawn anyway, symbol and all.
        .clipped()
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    #endif
}

#if !os(macOS)
/// The marks, each on one line, and one after another until the line runs out.
///
/// A mark that will not fit in what is left of a line is not squeezed into it — it starts the next
/// one whole, which is the same rule AppKit's text control keeps on the Mac once every break inside
/// a mark has been taken away. Where the policy allows only so many lines, what is left over goes,
/// and the ellipsis passed in last is placed to say so.
private struct MarksRow: Layout {
    var lines: Int?
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        placements(for: subviews, within: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        for placement in placements(for: subviews, within: bounds.width).items {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct Placements {
        var items: [(index: Int, origin: CGPoint, size: CGSize)]
        var size: CGSize
    }

    private func placements(for subviews: Subviews, within width: CGFloat) -> Placements {
        // The ellipsis comes last and is not a mark. It is placed only if a mark had to be left
        // out, and given no room at all otherwise, which draws nothing.
        let marks = subviews.dropLast()
        let ellipsis = subviews.index(before: subviews.endIndex)
        let ellipsisSize = subviews[ellipsis].sizeThatFits(.unspecified)

        var items: [(index: Int, origin: CGPoint, size: CGSize)] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var line = 1
        var leftOut = false

        for index in marks.indices {
            // Every subview has to be placed, so one that is left out is placed with no room at
            // all: unplaced, SwiftUI would put it at the origin, on top of the marks that fitted.
            var size = subviews[index].sizeThatFits(.unspecified)
            guard !leftOut else {
                items.append((index, CGPoint(x: width, y: 0), size))
                continue
            }
            size.width = min(size.width, width)
            if origin.x > 0, origin.x + size.width > width {
                guard lines.map({ line < $0 }) ?? true else {
                    leftOut = true
                    items.append((index, CGPoint(x: width, y: 0), size))
                    continue
                }
                line += 1
                origin = CGPoint(x: 0, y: origin.y + lineHeight + verticalSpacing)
                lineHeight = 0
            }
            items.append((index, origin, size))
            usedWidth = max(usedWidth, origin.x + size.width)
            lineHeight = max(lineHeight, size.height)
            origin.x += size.width + horizontalSpacing
        }

        if leftOut {
            // Room for it is made the only way there is: by giving up the last mark that fitted.
            var givenUp: [(index: Int, size: CGSize)] = []
            while origin.x + ellipsisSize.width > width, let last = items.popLast() {
                origin.x = last.origin.x
                givenUp.append((last.index, last.size))
            }
            items.append(contentsOf: givenUp.map { ($0.index, CGPoint(x: width, y: 0), $0.size) })
            items.append((ellipsis, origin, ellipsisSize))
            usedWidth = max(usedWidth, origin.x + ellipsisSize.width)
            lineHeight = max(lineHeight, ellipsisSize.height)
        } else {
            // Nothing was left out, so the ellipsis has nothing to say and goes past the edge too.
            items.append((ellipsis, CGPoint(x: width, y: 0), ellipsisSize))
        }

        return Placements(items: items, size: CGSize(width: usedWidth, height: origin.y + lineHeight))
    }
}
#endif

#if os(macOS)
private struct ThumbnailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: archiveFileLabelSpacing) {
            configuration.icon
            configuration.title
        }
    }
}
#endif
