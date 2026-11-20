import CoreGraphics
import CoreText
import Foundation

/// The sample PDF the in-memory shelf is stocked with, drawn here rather than carried as bytes.
///
/// Its pages deliberately disagree about their shape. A shelf of upright pages cannot show what the
/// two magnifications are for: on a page taller than the pane is, fitting the page and fitting the
/// width are the same number, and the controls look like duplicates of each other. Put a landscape
/// page next to a portrait one and the difference is the whole screen — which is also the case that
/// has to keep working, since each is measured against the page the reader is on rather than the
/// document.
enum SamplePDFDocument {
    /// US Letter, upright and on its side.
    private static let portrait = CGSize(width: 612, height: 792)
    private static let landscape = CGSize(width: 792, height: 612)

    static func data() -> Data {
        let pages: [(size: CGSize, title: String)] = [
            (portrait, "1 — Portrait"),
            (landscape, "2 — Landscape"),
            (portrait, "3 — Portrait"),
            (landscape, "4 — Landscape")
        ]

        let output = NSMutableData()
        var firstBox = CGRect(origin: .zero, size: portrait)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            return Data()
        }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            context.beginPage(mediaBox: &box)
            draw(page.title, in: box, into: context)
            context.endPage()
        }
        context.closePDF()
        return output as Data
    }

    /// A ruled page: a border, a title, and rules across it. The rules are what a magnification is
    /// read off — at a glance it is obvious whether a whole page is on screen or only its width.
    private static func draw(_ title: String, in box: CGRect, into context: CGContext) {
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(box)

        let margin: CGFloat = 48
        let frame = box.insetBy(dx: margin, dy: margin)
        context.setStrokeColor(gray: 0.2, alpha: 1)
        context.setLineWidth(2)
        context.stroke(frame)

        context.setStrokeColor(gray: 0.6, alpha: 1)
        context.setLineWidth(1)
        let ruleCount = 24
        let spacing = (frame.height - 80) / CGFloat(ruleCount)
        for rule in 0..<ruleCount {
            let y = frame.minY + spacing * CGFloat(rule) + 24
            context.move(to: CGPoint(x: frame.minX + 24, y: y))
            context.addLine(to: CGPoint(x: frame.maxX - 24, y: y))
        }
        context.strokePath()

        let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: CGColor(gray: 0, alpha: 1)
            ]
        ))
        context.textPosition = CGPoint(x: frame.minX + 24, y: frame.maxY - 56)
        CTLineDraw(line, context)
    }
}
