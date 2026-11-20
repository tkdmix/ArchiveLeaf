import Foundation

struct CompleteURLLinkifier: Sendable {
    func linkedText(_ text: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return AttributedString(text)
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        detector.enumerateMatches(in: text, range: fullRange) { result, _, _ in
            guard let result,
                  let url = result.url,
                  let range = Range(result.range, in: text) else { return }
            let matchedText = String(text[range])
            guard let scheme = explicitScheme(in: matchedText),
                  scheme.caseInsensitiveCompare(url.scheme ?? "") == .orderedSame else { return }
            mutable.addAttribute(.link, value: url, range: result.range)
        }
        return (try? AttributedString(mutable, including: \.foundation)) ?? AttributedString(text)
    }

    func completeURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range),
              match.range == range,
              let url = match.url,
              let scheme = explicitScheme(in: trimmed),
              scheme.caseInsensitiveCompare(url.scheme ?? "") == .orderedSame else { return nil }
        return url
    }

    func linkedJSONValues(_ text: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let characters = Array(text.utf16)
        var index = 0

        while index < characters.count {
            guard characters[index] == 0x22 else {
                index += 1
                continue
            }

            let openingQuote = index
            index += 1
            var isEscaped = false
            while index < characters.count {
                let character = characters[index]
                if character == 0x22, !isEscaped { break }
                if character == 0x5C {
                    isEscaped.toggle()
                } else {
                    isEscaped = false
                }
                index += 1
            }
            guard index < characters.count else { break }

            let closingQuote = index
            var next = closingQuote + 1
            while next < characters.count,
                  CharacterSet.whitespacesAndNewlines.contains(
                    UnicodeScalar(characters[next]) ?? UnicodeScalar(0)
                  ) {
                next += 1
            }

            // A JSON string followed by a colon is an object key, not a value.
            if next >= characters.count || characters[next] != 0x3A {
                let tokenRange = NSRange(
                    location: openingQuote,
                    length: closingQuote - openingQuote + 1
                )
                let tokenData = Data(String(decoding: characters[tokenRange.location..<(tokenRange.location + tokenRange.length)], as: UTF16.self).utf8)
                if let value = try? JSONSerialization.jsonObject(
                    with: tokenData,
                    options: .fragmentsAllowed
                ) as? String,
                   let url = completeURL(from: value) {
                    let rawValue = String(
                        decoding: characters[(openingQuote + 1)..<closingQuote],
                        as: UTF16.self
                    )
                    // Escaped JSON text does not map one-to-one to the displayed URL range.
                    // Keep those values unlinked rather than linking an incorrect substring.
                    if rawValue == value {
                        mutable.addAttribute(
                            .link,
                            value: url,
                            range: NSRange(
                                location: openingQuote + 1,
                                length: closingQuote - openingQuote - 1
                            )
                        )
                    }
                }
            }
            index = closingQuote + 1
        }

        return (try? AttributedString(mutable, including: \.foundation)) ?? AttributedString(text)
    }
}

private func explicitScheme(in value: String) -> String? {
    guard let colon = value.firstIndex(of: ":") else { return nil }
    let scheme = String(value[..<colon])
    guard !scheme.isEmpty,
          scheme.first?.isLetter == true,
          scheme.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else {
        return nil
    }
    return scheme
}
