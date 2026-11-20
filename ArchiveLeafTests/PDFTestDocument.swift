import CoreGraphics
import Foundation

/// A real PDF, made rather than pasted in.
///
/// Every PDF test needs bytes CoreGraphics and PDFKit both accept, and a base64 blob would say
/// nothing about the page it holds. Drawn here so a test can state its own page size and check what
/// came back against it.
enum PDFTestDocument {
    static func data(
        width: CGFloat = 200,
        height: CGFloat = 400,
        pageCount: Int = 1
    ) -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        for _ in 0..<pageCount {
            context.beginPage(mediaBox: &mediaBox)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
            context.endPage()
        }
        context.closePDF()
        return output as Data
    }
}
