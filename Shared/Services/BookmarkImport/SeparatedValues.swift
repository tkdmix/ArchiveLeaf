import Foundation

/// Reads a comma-separated file into rows of fields.
///
/// Written here rather than reached for outside: the shelf has no package dependencies, and the
/// only file this has to survive is one bookmarking app's export. It follows the ordinary rules —
/// quoted fields may hold commas, newlines, and doubled quotes — because a bookmark's title and
/// its excerpt hold all three.
enum SeparatedValues {
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var hasContent = false
        var characters = text.makeIterator()
        var pending: Character?

        func endField() {
            fields.append(field)
            field = ""
        }

        func endRow() {
            endField()
            // A trailing newline ends the file rather than starting an empty last row.
            if hasContent { rows.append(fields) }
            fields = []
            hasContent = false
        }

        while let character = pending ?? characters.next() {
            pending = nil
            if isQuoted {
                guard character == "\"" else {
                    field.append(character)
                    hasContent = true
                    continue
                }
                if let next = characters.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isQuoted = false
                        pending = next
                    }
                } else {
                    isQuoted = false
                }
                hasContent = true
                continue
            }

            switch character {
            case "\"":
                isQuoted = true
                hasContent = true
            case ",":
                endField()
                hasContent = true
            // A Windows line ending is one Swift character, not two. Matching only "\r" left every
            // row of a CSV written that way joined to the next.
            case "\r\n", "\r", "\n":
                endRow()
            default:
                field.append(character)
                hasContent = true
            }
        }
        if hasContent || !fields.isEmpty { endRow() }
        return rows
    }
}
