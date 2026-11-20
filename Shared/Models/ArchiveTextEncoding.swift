import Foundation

/// The text encodings ArchiveLeaf can decode.
///
/// The raw value is the durable identifier stored in `ArchiveFile.sourceEncoding` and
/// `ArchiveFile.sourceEncodingOverride`. Detection records what it recognized at import time;
/// the override lets a user correct a wrong guess without re-importing immutable content.
enum ArchiveTextEncoding: String, CaseIterable, Codable, Sendable {
    case utf8 = "utf-8"
    case shiftJIS = "shift_jis"
    case windows31J = "windows-31j"
    case eucJP = "euc-jp"
    case iso2022JP = "iso-2022-jp"
    case utf16BE = "utf-16be"
    case utf16LE = "utf-16le"
    case utf32BE = "utf-32be"
    case utf32LE = "utf-32le"

    /// The order detection attempts when there is no byte-order mark.
    ///
    /// Strict Shift_JIS is tried before Windows-31J so a file that stays inside JIS X 0208 is
    /// recorded as such, and only a file that actually needs the vendor extensions is recorded as
    /// Windows-31J. The two still disagree on shared code points, so the choice remains overridable.
    static let detectionOrder: [ArchiveTextEncoding] = [
        .utf8, .shiftJIS, .windows31J, .eucJP, .iso2022JP
    ]

    static func named(_ identifier: String?) -> ArchiveTextEncoding? {
        guard let identifier else { return nil }
        return ArchiveTextEncoding(rawValue: identifier.lowercased())
    }

    var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .shiftJIS: "Shift_JIS (JIS X 0208)"
        case .windows31J: "Windows-31J (CP932)"
        case .eucJP: "EUC-JP"
        case .iso2022JP: "ISO-2022-JP"
        case .utf16BE: "UTF-16 BE"
        case .utf16LE: "UTF-16 LE"
        case .utf32BE: "UTF-32 BE"
        case .utf32LE: "UTF-32 LE"
        }
    }

    func decode(_ data: Data) -> String? {
        String(data: data, encoding: stringEncoding)
    }

    /// `String.Encoding.shiftJIS` is CP932, not JIS X 0208, so it is used for Windows-31J.
    /// Strict Shift_JIS is only reachable through the CoreFoundation encoding. The two differ on
    /// vendor extensions (Windows-31J accepts circled numbers such as `0x8740`) and on shared code
    /// points (`0x8160` is `〜` in Shift_JIS and `～` in Windows-31J), which is why both are offered.
    private var stringEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .shiftJIS: String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
            )
        )
        case .windows31J: .shiftJIS
        case .eucJP: .japaneseEUC
        case .iso2022JP: .iso2022JP
        case .utf16BE: .utf16BigEndian
        case .utf16LE: .utf16LittleEndian
        case .utf32BE: .utf32BigEndian
        case .utf32LE: .utf32LittleEndian
        }
    }
}
