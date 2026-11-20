import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns Markdown source into one `AttributedString` that keeps its block structure.
///
/// `AttributedString(markdown:)` records blocks in `presentationIntent` rather than in the text
/// itself, so rendering its result directly runs every heading, paragraph, and list item together
/// on a single line. Rebuild it with a blank line between blocks, heading fonts, and list markers.
///
/// The result stays a single attributed string rather than a stack of views so that in-document
/// search keeps operating on one continuous text.
#if os(macOS)
typealias PlatformFont = NSFont
#else
typealias PlatformFont = UIFont
#endif

enum MarkdownAttributedText {
    #if os(macOS)
    private static let bodyStyle: PlatformFont.TextStyle = .body
    #else
    private static let bodyStyle: PlatformFont.TextStyle = .body
    #endif

    static func attributedString(from source: String) -> AttributedString {
        guard let parsed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return AttributedString(source)
        }

        var result = AttributedString()
        var previousIntent: PresentationIntent?
        for block in blocks(in: parsed) {
            var text = trimmingWhitespace(block.text)
            guard !text.characters.isEmpty else { continue }

            if let marker = listMarker(for: block.intent) {
                text = AttributedString(marker) + text
            }
            // Every run carries a font: a text view draws whatever a run does not name in its own
            // default, which is not the body size this document should be set in.
            let blockFont = font(for: block.intent) ?? .preferredFont(forTextStyle: bodyStyle)
            // Colour as well as font: a text view draws a run that names neither in its own
            // defaults, and the body came out dim against a dark window. Both are dynamic colours,
            // so they still follow light and dark.
            #if os(macOS)
            let appKitText = NSMutableAttributedString(text)
            appKitText.addAttributes(
                [.font: blockFont, .foregroundColor: NSColor.labelColor],
                range: NSRange(location: 0, length: appKitText.length)
            )
            text = AttributedString(appKitText)
            #else
            text.uiKit.font = blockFont
            text.uiKit.foregroundColor = .label
            #endif
            if !result.characters.isEmpty {
                let isSameList = listIdentity(of: block.intent) != nil
                    && listIdentity(of: block.intent) == listIdentity(of: previousIntent)
                result += AttributedString(isSameList ? "\n" : "\n\n")
            }
            result += text
            previousIntent = block.intent
        }
        return result.characters.isEmpty ? parsed : result
    }

    private struct Block {
        var intent: PresentationIntent?
        var text: AttributedString
    }

    /// Runs belonging to the same block share one `presentationIntent`, because inline styling
    /// does not change it and every block carries its own identity.
    private static func blocks(in parsed: AttributedString) -> [Block] {
        var blocks: [Block] = []
        for run in parsed.runs {
            let slice = AttributedString(parsed[run.range])
            if let last = blocks.last, last.intent == run.presentationIntent {
                blocks[blocks.count - 1].text += slice
            } else {
                blocks.append(Block(intent: run.presentationIntent, text: slice))
            }
        }
        return blocks
    }

    /// Platform fonts rather than SwiftUI's: the document is drawn by a text view, and only these
    /// survive the crossing into `NSAttributedString`.
    private static func font(for intent: PresentationIntent?) -> PlatformFont? {
        guard let intent else { return nil }
        for component in intent.components {
            switch component.kind {
            case .header(let level):
                switch level {
                case 1: return bold(.title1)
                case 2: return bold(.title2)
                case 3: return bold(.title3)
                default: return bold(.headline)
                }
            case .codeBlock:
                return .monospacedSystemFont(
                    ofSize: PlatformFont.preferredFont(forTextStyle: bodyStyle).pointSize,
                    weight: .regular
                )
            default:
                continue
            }
        }
        return nil
    }

    private static func bold(_ style: PlatformFont.TextStyle) -> PlatformFont {
        let base = PlatformFont.preferredFont(forTextStyle: style)
        #if os(macOS)
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        #else
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
        #endif
    }

    /// Identifies the list a block belongs to, so consecutive items stay on adjacent lines
    /// instead of being spread apart like separate blocks.
    private static func listIdentity(of intent: PresentationIntent?) -> Int? {
        intent?.components.first { component in
            switch component.kind {
            case .orderedList, .unorderedList: true
            default: false
            }
        }?.identity
    }

    private static func listMarker(for intent: PresentationIntent?) -> String? {
        guard let intent else { return nil }
        var ordinal: Int?
        var isOrdered = false
        var isUnordered = false

        for component in intent.components {
            switch component.kind {
            case .listItem(let value): ordinal = value
            case .orderedList: isOrdered = true
            case .unorderedList: isUnordered = true
            default: continue
            }
        }

        if isOrdered, let ordinal { return "\(ordinal). " }
        return isUnordered ? "• " : nil
    }

    private static func trimmingWhitespace(_ text: AttributedString) -> AttributedString {
        var result = text
        while let first = result.characters.first, first.isWhitespace {
            result.removeSubrange(result.startIndex..<result.index(afterCharacter: result.startIndex))
        }
        while let last = result.characters.last, last.isWhitespace {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex)
        }
        return result
    }
}
